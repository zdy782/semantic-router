package handlers

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

// openClawSkillPackDir returns the server-owned directory holding known
// skill packs (each pack is a subdirectory containing SKILL.md and optional
// assets). Only these server-controlled copies are used when materializing
// skills into a workspace; content is never extracted from the caller-
// selected image.
//
// The Dashboard image runs in /app and packages the packs at /app/skills;
// the source tree keeps them at dashboard/backend/skillpacks. The deployed
// location is preferred so provisioning without an environment override
// resolves the bundled packs.
func openClawSkillPackDir() string {
	if p := strings.TrimSpace(os.Getenv("OPENCLAW_SKILL_PACKS_PATH")); p != "" {
		return p
	}
	if wd, err := os.Getwd(); err == nil {
		return openClawSkillPackDirIn(wd)
	}
	return "skillpacks"
}

// openClawSkillPackDirIn picks the skill-pack directory under wd, preferring
// the deployed "skills" layout and falling back to the source-tree
// "skillpacks" layout.
func openClawSkillPackDirIn(wd string) string {
	for _, name := range []string{"skills", "skillpacks"} {
		candidate := filepath.Join(wd, name)
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate
		}
	}
	return filepath.Join(wd, "skillpacks")
}

// prepareProvisionWorkspace creates the workspace subtree and returns the
// resolved workspace and skills directories. validateProvisionPaths already
// proved wsDir itself stays inside the container data directory, but the
// output directories below it must be checked too: a pre-existing
// workspace/skills or workspace/memory symlink pointing outside would
// otherwise be resolved and treated as the trusted root for skill
// materialization, letting writes escape the workspace.
func prepareProvisionWorkspace(wsDir string) (wsEval, skillsRoot string, err error) {
	if err := os.MkdirAll(wsDir, 0o755); err != nil {
		return "", "", err
	}
	wsEval, err = resolveExistingDir(wsDir)
	if err != nil {
		return "", "", fmt.Errorf("failed to resolve workspace: %w", err)
	}
	for _, sub := range []string{"skills", "memory"} {
		resolved, mkErr := containedMkdirAll(wsEval, []string{sub}, wsEval)
		if mkErr != nil {
			return "", "", fmt.Errorf("invalid workspace %s dir: %w", sub, mkErr)
		}
		if sub == "skills" {
			skillsRoot = resolved
		}
	}
	return wsEval, skillsRoot, nil
}

// openClawProvisionGID returns the numeric group ID provisioned containers
// join via --group-add and that owns the workspace/state trees group-wise.
// It defaults to the Dashboard's own primary group; on deployments where the
// Dashboard group also owns Dashboard state (e.g. the host-socket topology's
// prepare_shared_tree), administrators should set OPENCLAW_PROVISION_GID to
// a dedicated group so workers cannot write Dashboard state through it. The
// Dashboard process must be a member of the configured group to chgrp files.
// A malformed value is an error, not a fallback: silently joining the
// Dashboard's group would defeat the isolation the administrator asked for.
func openClawProvisionGID() (int, error) {
	raw, configured := os.LookupEnv("OPENCLAW_PROVISION_GID")
	if !configured {
		return os.Getgid(), nil
	}
	gid, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || gid <= 0 {
		return 0, fmt.Errorf("invalid OPENCLAW_PROVISION_GID %q: must be a positive numeric group ID", raw)
	}
	return gid, nil
}

// relabelTreeForGroup applies group-writable modes (0770 dirs, 0660 files)
// and, when gid differs from the Dashboard's own primary group, chgrps
// entries to gid — but only on entries the Dashboard owns. Files the worker
// created under a previous run belong to the worker's UID; the Dashboard
// cannot and need not touch them because the worker already has owner
// access no matter which group it joins.
// Symlinks are never followed, so an escaping link cannot redirect a chmod
// outside the tree.
func relabelTreeForGroup(dir string, gid int) error {
	chgrp := gid != os.Getgid()
	uid := os.Getuid()
	return filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		if !d.IsDir() && !d.Type().IsRegular() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if st, ok := info.Sys().(*syscall.Stat_t); !ok || int(st.Uid) != uid {
			// Not Dashboard-owned (e.g. worker-created state) — leave
			// modes and group alone; the owner keeps its own access.
			return nil
		}
		if chgrp {
			if err := os.Chown(p, -1, gid); err != nil {
				return fmt.Errorf("failed to set group %d on %s: %w", gid, p, err)
			}
		}
		if d.IsDir() {
			return os.Chmod(p, 0o770)
		}
		return os.Chmod(p, 0o660)
	})
}

// makeWorkspaceWritable grants the provisioned container's non-root image
// user (e.g. node/1000) write access to the bind-mounted workspace via the
// provision group (see relabelTreeForGroup and --group-add).
func makeWorkspaceWritable(wsDir string, gid int) error {
	return relabelTreeForGroup(wsDir, gid)
}

// prepareProvisionStateDir creates the container state directory inside the
// validated container data dir and relabels the whole subtree for the same
// --group-add mechanism as the workspace, so sessions survive both
// reprovisioning and provision-group changes.
func prepareProvisionStateDir(cDirEval string, gid int) (string, error) {
	stateDir, err := containedMkdirAll(cDirEval, []string{"state"}, cDirEval)
	if err != nil {
		return "", fmt.Errorf("invalid container state dir: %w", err)
	}
	if err := relabelTreeForGroup(stateDir, gid); err != nil {
		return "", fmt.Errorf("failed to set state dir permissions: %w", err)
	}
	return stateDir, nil
}

// validateOpenClawSkillPackID mirrors the strict catalog ID pattern so a pack
// directory name can never carry path separators, traversal segments, or
// aliases.
func validateOpenClawSkillPackID(skillID string) error {
	if !openClawSkillIDPattern.MatchString(skillID) {
		return fmt.Errorf("invalid skill ID %q", skillID)
	}
	return nil
}

// resolveOpenClawSkillPack resolves skillID to a server-owned pack directory
// and proves, after symlink-aware evaluation, that both the pack directory
// and its SKILL.md stay inside the skill-pack root. It rejects unknown IDs,
// aliases, and any symlink that escapes the root.
func resolveOpenClawSkillPack(skillID string) (packDir string, skillFile string, err error) {
	if invalid := validateOpenClawSkillPackID(skillID); invalid != nil {
		return "", "", invalid
	}

	root := openClawSkillPackDir()
	rootAbs, err := filepath.Abs(root)
	if err != nil {
		return "", "", fmt.Errorf("failed to resolve skill pack root: %w", err)
	}
	rootEval, err := filepath.EvalSymlinks(rootAbs)
	if err != nil {
		return "", "", fmt.Errorf("failed to resolve skill pack root: %w", err)
	}

	candidate := filepath.Join(rootEval, skillID)
	candidateEval, err := filepath.EvalSymlinks(candidate)
	if err != nil {
		return "", "", fmt.Errorf("unknown skill ID %q", skillID)
	}
	if !pathWithinDir(candidateEval, rootEval) {
		return "", "", fmt.Errorf("unknown skill ID %q", skillID)
	}

	skillPath := filepath.Join(candidateEval, "SKILL.md")
	skillEval, err := filepath.EvalSymlinks(skillPath)
	if err != nil {
		return "", "", fmt.Errorf("unknown skill ID %q", skillID)
	}
	if !pathWithinDir(skillEval, rootEval) {
		return "", "", fmt.Errorf("unknown skill ID %q", skillID)
	}
	return candidateEval, skillEval, nil
}

// pathWithinDir reports whether target is dir itself or nested inside dir.
// Both paths must already be symlink-resolved and absolute.
func pathWithinDir(target, dir string) bool {
	if target == dir {
		return true
	}
	if dir == "" || dir == "/" {
		return false
	}
	rel, err := filepath.Rel(dir, target)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// copyOpenClawSkillPack copies the server-owned skill pack into the given
// workspace skills directory under the pack's strict ID. Every destination
// component (the skills root, the per-skill directory, and each written
// file) is resolved symlink-aware and proven contained inside the trusted
// workspace skills root before any write; pre-existing symlinks pointing
// outside the workspace are rejected instead of followed.
func copyOpenClawSkillPack(skillID, skillsRoot string) error {
	if invalid := validateOpenClawSkillPackID(skillID); invalid != nil {
		return invalid
	}

	rootEval, err := resolveExistingDir(skillsRoot)
	if err != nil {
		return fmt.Errorf("failed to resolve workspace skills dir: %w", err)
	}

	packDir, _, err := resolveOpenClawSkillPack(skillID)
	if err != nil {
		return err
	}

	destDir, err := containedMkdirAll(rootEval, []string{skillID}, rootEval)
	if err != nil {
		return err
	}

	return copyDirWithinRoot(packDir, destDir, rootEval)
}

// resolveExistingDir returns the symlink-resolved absolute path of an
// existing directory, or an error when it is missing or not a directory.
func resolveExistingDir(dir string) (string, error) {
	abs, err := filepath.Abs(dir)
	if err != nil {
		return "", err
	}
	eval, err := filepath.EvalSymlinks(abs)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(eval)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("%s is not a directory", dir)
	}
	return eval, nil
}

// containedMkdirAll creates the missing components under root and returns
// the fully resolved path. Each component that already exists must resolve
// (symlink-aware) inside root; components created here are fresh
// non-symlink directories. The final component is never created through a
// symlink.
func containedMkdirAll(root string, components []string, trustedRoot string) (string, error) {
	trustedRootEval, err := resolveExistingDir(trustedRoot)
	if err != nil {
		return "", fmt.Errorf("failed to resolve trusted root: %w", err)
	}
	rootEval, err := resolveExistingDir(root)
	if err != nil {
		return "", fmt.Errorf("failed to resolve destination root: %w", err)
	}
	if !pathWithinDir(rootEval, trustedRootEval) {
		return "", fmt.Errorf("destination root resolves outside the workspace")
	}

	target := filepath.Join(append([]string{rootEval}, components...)...)
	rel, err := filepath.Rel(trustedRootEval, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("destination resolves outside the workspace")
	}

	rootFS, err := os.OpenRoot(trustedRootEval)
	if err != nil {
		return "", fmt.Errorf("failed to open trusted root: %w", err)
	}
	defer func() { _ = rootFS.Close() }()

	// Root.MkdirAll resolves every path component relative to an opened root
	// and refuses symbolic links that escape it, closing the Lstat/Mkdir
	// TOCTOU window present in path-based creation.
	if mkdirErr := rootFS.MkdirAll(rel, 0o755); mkdirErr != nil {
		return "", fmt.Errorf("failed to create contained dir: %w", mkdirErr)
	}

	resolved, err := filepath.EvalSymlinks(filepath.Join(trustedRootEval, rel))
	if err != nil {
		return "", fmt.Errorf("failed to resolve contained dir: %w", err)
	}
	if !pathWithinDir(resolved, trustedRootEval) {
		return "", fmt.Errorf("contained dir resolves outside the workspace")
	}
	return resolved, nil
}

// writeContainedFile writes data to name inside dirRef only when the target
// does not exist or is a regular file whose resolved path stays inside the
// trusted root. A symlink at the destination is rejected, never followed.
func writeContainedFile(dirRef, trustedRoot, name string, data []byte, perm os.FileMode) error {
	trustedRootEval, err := resolveExistingDir(trustedRoot)
	if err != nil {
		return fmt.Errorf("failed to resolve trusted root: %w", err)
	}
	dirEval, err := resolveExistingDir(dirRef)
	if err != nil {
		return fmt.Errorf("failed to resolve destination dir: %w", err)
	}
	if !pathWithinDir(dirEval, trustedRootEval) {
		return fmt.Errorf("destination dir resolves outside the workspace")
	}

	relDir, err := filepath.Rel(trustedRootEval, dirEval)
	if err != nil || relDir == ".." || strings.HasPrefix(relDir, ".."+string(filepath.Separator)) {
		return fmt.Errorf("destination dir resolves outside the workspace")
	}
	relTarget := filepath.Join(relDir, name)

	rootFS, err := os.OpenRoot(trustedRootEval)
	if err != nil {
		return fmt.Errorf("failed to open trusted root: %w", err)
	}
	defer func() { _ = rootFS.Close() }()

	// Preserve the deterministic rejection of an already-present destination
	// symlink. Root.WriteFile below provides the race-safe boundary: even if
	// the path is swapped after this check, it cannot resolve outside root.
	if info, statErr := rootFS.Lstat(relTarget); statErr == nil {
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("refusing to write through symlink %s", name)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("refusing to overwrite non-regular file %s", name)
		}
	} else if !os.IsNotExist(statErr) {
		return statErr
	}

	return rootFS.WriteFile(relTarget, data, perm)
}

// copyDirWithinRoot recursively copies src into dst, refusing any entry
// (after symlink resolution) that would resolve outside root.
func copyDirWithinRoot(src, dst, root string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return fmt.Errorf("failed to read skill pack: %w", err)
	}

	// Deterministic order for reproducible provisioning.
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)

	for _, name := range names {
		entryPath := filepath.Join(src, name)
		info, statErr := os.Lstat(entryPath)
		if statErr != nil {
			return fmt.Errorf("failed to stat %s: %w", name, statErr)
		}

		entryEval, evalErr := filepath.EvalSymlinks(entryPath)
		if evalErr != nil {
			// Dangling symlink or unreadable entry: skip, never copy.
			continue
		}
		if !pathWithinDir(entryEval, root) && !pathWithinDir(entryEval, src) {
			// Symlinked pack content may legitimately point elsewhere inside
			// the pack, but never outside the server-owned root.
			return fmt.Errorf("skill pack entry %q resolves outside the skill pack root", name)
		}

		switch {
		case info.IsDir():
			subDir, mkdirErr := containedMkdirAll(dst, []string{name}, root)
			if mkdirErr != nil {
				return fmt.Errorf("failed to create dir %s: %w", name, mkdirErr)
			}
			if copyErr := copyDirWithinRoot(entryEval, subDir, root); copyErr != nil {
				return copyErr
			}
		case info.Mode().IsRegular():
			data, readErr := os.ReadFile(entryEval)
			if readErr != nil {
				return fmt.Errorf("failed to read %s: %w", name, readErr)
			}
			if writeErr := writeContainedFile(dst, root, name, data, 0o644); writeErr != nil {
				return fmt.Errorf("failed to write %s: %w", name, writeErr)
			}
		default:
			// Skip sockets, devices, and symlinks: never copy them into a
			// provisioned workspace.
		}
	}
	return nil
}
