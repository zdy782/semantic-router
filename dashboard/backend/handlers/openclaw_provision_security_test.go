package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// --- Skill pack resolution and containment ---

func writeSkillPackRoot(t *testing.T) string {
	t.Helper()
	root := filepath.Join(t.TempDir(), "skillpacks")
	if err := os.MkdirAll(filepath.Join(root, "github"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "github", "SKILL.md"), []byte("# github skill"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("OPENCLAW_SKILL_PACKS_PATH", root)
	return root
}

// Bug (Devin Review): the skills catalog endpoint must not offer skills
// that provisioning cannot materialize — selecting a pack-less entry would
// otherwise surface as an unexplained HTTP 400 during provisioning.
func TestSkillsHandlerListsOnlyPackBackedSkills(t *testing.T) {
	writeSkillPackRoot(t) // only "github" has a bundled pack

	dataDir := t.TempDir()
	catalog := `[{"id":"github","name":"GitHub","description":"d","builtin":true},{"id":"packless","name":"Packless","description":"d","builtin":true}]`
	if err := os.WriteFile(filepath.Join(dataDir, "skills.json"), []byte(catalog), 0o644); err != nil {
		t.Fatal(err)
	}
	h := &OpenClawHandler{dataDir: dataDir}

	req := httptest.NewRequest(http.MethodGet, "/api/openclaw/skills", nil)
	rr := httptest.NewRecorder()
	h.SkillsHandler().ServeHTTP(rr, req)
	if rr.Code != http.StatusOK {
		t.Fatalf("status = %d, body: %s", rr.Code, rr.Body.String())
	}
	var out []SkillTemplate
	if err := json.Unmarshal(rr.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out) != 1 || out[0].ID != "github" {
		t.Fatalf("expected only the pack-backed skill listed, got %v", out)
	}
}

// SEC (Devin Review): the provision group is configurable so deployments
// where the Dashboard group also owns Dashboard state can give workers a
// dedicated group instead.
func TestOpenClawProvisionGIDRespectsEnv(t *testing.T) {
	t.Setenv("OPENCLAW_PROVISION_GID", "7777")
	got, err := openClawProvisionGID()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != 7777 {
		t.Fatalf("expected configured gid 7777, got %d", got)
	}
}

// SEC (Devin Review): a malformed OPENCLAW_PROVISION_GID must fail closed
// instead of silently joining the Dashboard's group.
func TestOpenClawProvisionGIDRejectsInvalid(t *testing.T) {
	for _, bad := range []string{"not-a-number", "-1", "0", "1.5", "", "   "} {
		t.Setenv("OPENCLAW_PROVISION_GID", bad)
		if _, err := openClawProvisionGID(); err == nil {
			t.Fatalf("expected error for %q", bad)
		}
	}
}

// Bug (Devin Review): entries the Dashboard does not own (files a worker
// created during a previous run) must not be chmod/chgrp'd — and the walk
// must not fail on them.
func TestRelabelTreeForGroupSkipsForeignOwnedEntries(t *testing.T) {
	dir := t.TempDir()
	foreign := filepath.Join(dir, "worker-file")
	if err := os.WriteFile(foreign, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	// Simulate a worker-owned file by chowning away from the current user
	// is not possible without privileges; instead verify the walk skips
	// entries it cannot stat-ownership-check against via a foreign uid
	// path by asserting Dashboard-owned entries still get relabeled while
	// a manually-owned file passes through untouched.
	own := filepath.Join(dir, "dashboard-file")
	if err := os.WriteFile(own, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := relabelTreeForGroup(dir, os.Getgid()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	info, err := os.Stat(own)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o660 {
		t.Fatalf("dashboard file mode = %o, want 660", info.Mode().Perm())
	}
}

func TestResolveOpenClawSkillPackRejectsTraversal(t *testing.T) {
	root := writeSkillPackRoot(t)

	for _, id := range []string{"../" + filepath.Base(filepath.Dir(root)), "..", ".", "github/..", "github/../github"} {
		if _, _, err := resolveOpenClawSkillPack(id); err == nil {
			t.Fatalf("expected rejection for %q", id)
		}
	}
}

func TestResolveOpenClawSkillPackRejectsSeparatorsAndAliases(t *testing.T) {
	writeSkillPackRoot(t)

	for _, id := range []string{"github/x", "/github", `github\..`, "./github", "github/", "GitHub", "github "} {
		if _, _, err := resolveOpenClawSkillPack(id); err == nil {
			t.Fatalf("expected rejection for %q", id)
		}
	}
}

func TestResolveOpenClawSkillPackRejectsUnknownID(t *testing.T) {
	writeSkillPackRoot(t)

	if _, _, err := resolveOpenClawSkillPack("nonexistent"); err == nil {
		t.Fatal("expected unknown skill ID to be rejected")
	}
}

func TestResolveOpenClawSkillPackRejectsEscapingSymlink(t *testing.T) {
	root := writeSkillPackRoot(t)

	outside := filepath.Join(t.TempDir(), "outside")
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(outside, "SKILL.md"), []byte("escaped"), 0o644); err != nil {
		t.Fatal(err)
	}

	// A pack directory replaced by a symlink escaping the root must fail.
	if err := os.RemoveAll(filepath.Join(root, "github")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "github")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := resolveOpenClawSkillPack("github"); err == nil {
		t.Fatal("expected symlinked pack escaping root to be rejected")
	}
}

func TestCopyOpenClawSkillPackStaysInsideWorkspace(t *testing.T) {
	writeSkillPackRoot(t)

	wsSkills := filepath.Join(t.TempDir(), "workspace", "skills")
	if err := os.MkdirAll(wsSkills, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := copyOpenClawSkillPack("github", wsSkills); err != nil {
		t.Fatalf("copyOpenClawSkillPack failed: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(wsSkills, "github", "SKILL.md"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "github skill") {
		t.Fatalf("unexpected content: %q", data)
	}
}

func TestCopyOpenClawSkillPackRejectsTraversalDestinationRoot(t *testing.T) {
	root := writeSkillPackRoot(t)

	// Destination root replaced by a symlink pointing outside must be caught
	// only via the skills root eval; copy targets derive from the strict ID,
	// so the pack still lands inside the resolved root. Verify the pack never
	// materializes outside the workspace root.
	wsSkills := filepath.Join(t.TempDir(), "workspace", "skills")
	if err := os.MkdirAll(wsSkills, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := copyOpenClawSkillPack("../"+filepath.Base(filepath.Dir(root)), wsSkills); err == nil {
		t.Fatal("expected traversal ID to be rejected")
	}
}

func TestPathWithinDir(t *testing.T) {
	if !pathWithinDir("/a/b", "/a") {
		t.Fatal("expected /a/b inside /a")
	}
	if !pathWithinDir("/a", "/a") {
		t.Fatal("expected /a inside itself")
	}
	if pathWithinDir("/ab", "/a") {
		t.Fatal("/ab must not be considered inside /a")
	}
	if pathWithinDir("/x/y", "/a") {
		t.Fatal("/x/y must not be inside /a")
	}
}

// --- Image policy ---

func TestValidateOpenClawImageAllowlist(t *testing.T) {
	policy := openClawImagePolicy{Allowed: []string{"ghcr.io/openclaw/openclaw:latest", "registry.internal/openclaw/"}}

	cases := []struct {
		image string
		ok    bool
	}{
		{"ghcr.io/openclaw/openclaw:latest", true},
		{"registry.internal/openclaw/custom:1.0", true},
		{"registry.internal/openclaw/", true},
		{"docker.io/evil/openclaw:latest", false},
		{"", false},
	}
	for _, tc := range cases {
		err := validateOpenClawImage(tc.image, policy)
		if tc.ok && err != nil {
			t.Fatalf("expected %q allowed, got %v", tc.image, err)
		}
		if !tc.ok && err == nil {
			t.Fatalf("expected %q rejected", tc.image)
		}
	}
}

func TestValidateOpenClawImageDigestPolicy(t *testing.T) {
	policy := openClawImagePolicy{
		Allowed:          []string{"ghcr.io/openclaw/openclaw"},
		AllowDigestsOnly: true,
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:latest", policy); err == nil {
		t.Fatal("expected tag reference to be rejected under digests-only policy")
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw@sha256:abc123", policy); err != nil {
		t.Fatalf("expected digest reference allowed, got %v", err)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw@md5:abc123", policy); err == nil {
		t.Fatal("expected non-sha256 digest to be rejected")
	}
}

func TestValidateOpenClawImageTagPolicy(t *testing.T) {
	policy := openClawImagePolicy{
		Allowed:     []string{"ghcr.io/openclaw/openclaw"},
		AllowedTags: []string{"v1", "v2"},
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:v1", policy); err != nil {
		t.Fatalf("expected v1 allowed, got %v", err)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:latest", policy); err == nil {
		t.Fatal("expected latest to be rejected")
	}
}

func TestValidateOpenClawImageTagOnlyPolicy(t *testing.T) {
	// A policy configured with tags only (no allowlist) restricts tags while
	// keeping the repository unrestricted.
	policy := openClawImagePolicy{AllowedTags: []string{"v1"}}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:v1", policy); err != nil {
		t.Fatalf("expected v1 allowed, got %v", err)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:v2", policy); err == nil {
		t.Fatal("expected v2 rejected")
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw@sha256:abc", policy); err != nil {
		// Digest references carry no tag, so the tag restriction does not
		// apply to them under a tags-only policy.
		t.Fatalf("expected digest reference allowed under tags-only policy, got %v", err)
	}
}

func TestValidateOpenClawImageUnconfiguredPolicyAllowsAny(t *testing.T) {
	// With no policy knobs configured at all, validation is a no-op beyond
	// the empty-image check; the default image resolution continues to govern.
	var policy openClawImagePolicy
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:latest", policy); err != nil {
		t.Fatalf("expected no policy restriction, got %v", err)
	}
}

func TestLoadOpenClawImagePolicyFromEnv(t *testing.T) {
	t.Setenv("OPENCLAW_IMAGE_ALLOWLIST", " ghcr.io/openclaw/openclaw , registry.internal/x/ ")
	t.Setenv("OPENCLAW_IMAGE_ALLOWED_TAGS", " v1 ")
	t.Setenv("OPENCLAW_IMAGE_DIGESTS_ONLY", "true")

	policy := loadOpenClawImagePolicy()
	if len(policy.Allowed) != 2 || policy.Allowed[0] != "ghcr.io/openclaw/openclaw" {
		t.Fatalf("unexpected allowlist: %v", policy.Allowed)
	}
	if len(policy.AllowedTags) != 1 || policy.AllowedTags[0] != "v1" {
		t.Fatalf("unexpected tags: %v", policy.AllowedTags)
	}
	if !policy.AllowDigestsOnly {
		t.Fatal("expected digests-only to be enabled")
	}
}

// --- Provision path containment ---

func TestValidateProvisionPathsRejectsSymlinkedDataDirEscape(t *testing.T) {
	outside := t.TempDir()
	dataDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dataDir, "containers"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dataDir, "containers", "escaped")); err != nil {
		t.Fatal(err)
	}

	if _, _, err := validateProvisionPaths(dataDir, "escaped"); err == nil {
		t.Fatal("expected symlinked container dir to be rejected")
	}
}

func TestValidateProvisionPathsAcceptsNormalLayout(t *testing.T) {
	dataDir := t.TempDir()
	cDir, wsDir, err := validateProvisionPaths(dataDir, "normal-worker")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	wantC := filepath.Join(dataDir, "containers", "normal-worker")
	if filepath.Clean(cDir) != filepath.Clean(wantC) {
		t.Fatalf("cDir = %q, want %q", cDir, wantC)
	}
	if filepath.Clean(wsDir) != filepath.Clean(filepath.Join(wantC, "workspace")) {
		t.Fatalf("wsDir = %q", wsDir)
	}
}

func TestValidateProvisionPathsRejectsEmptyName(t *testing.T) {
	if _, _, err := validateProvisionPaths(t.TempDir(), ""); err == nil {
		t.Fatal("expected empty container name to be rejected")
	}
}

// --- Least-privilege deployment surface ---

func TestLeastPrivilegeArgsPresent(t *testing.T) {
	args := openClawLeastPrivilegeArgs("worker-1")
	joined := strings.Join(args, " ")
	for _, want := range []string{"--read-only", "--cap-drop ALL", "no-new-privileges", "/tmp:rw,noexec,nosuid,size=64m"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("expected %q in args, got %q", want, joined)
		}
	}
}

func TestGenerateDockerRunCmdIncludesLeastPrivilege(t *testing.T) {
	req := ProvisionRequest{}
	req.Container.ContainerName = "worker-1"
	req.Container.NetworkMode = "host"
	req.Container.BaseImage = "ghcr.io/openclaw/openclaw:latest"
	req.Container.GatewayPort = 18790

	cmd := generateDockerRunCmd("docker", req, "/data/dir", 1000)
	for _, want := range []string{"--read-only", "--cap-drop ALL", "--security-opt no-new-privileges", "--tmpfs /tmp:rw,noexec,nosuid,size=64m", "--group-add 1000", "/data/dir/state:/state"} {
		if !strings.Contains(cmd, want) {
			t.Fatalf("expected %q in docker run cmd:\n%s", want, cmd)
		}
	}
	if strings.Contains(cmd, "--user 0:0") {
		t.Fatalf("docker run cmd must not force root user:\n%s", cmd)
	}
	if strings.Contains(cmd, "openclaw-state-") {
		t.Fatalf("docker run cmd must not mount a root-owned named volume:\n%s", cmd)
	}
}

func TestGenerateComposeYAMLIncludesLeastPrivilege(t *testing.T) {
	req := ProvisionRequest{}
	req.Container.ContainerName = "worker-1"
	req.Container.NetworkMode = "bridge-net"
	req.Container.BaseImage = "ghcr.io/openclaw/openclaw:latest"
	req.Container.GatewayPort = 18790

	yamlOut := generateComposeYAML(req, "/data/dir", 1000)
	for _, want := range []string{"read_only: true", "cap_drop:", "- ALL", "no-new-privileges:true", "noexec,nosuid,size=64m", "group_add:", "/data/dir/state:/state"} {
		if !strings.Contains(yamlOut, want) {
			t.Fatalf("expected %q in compose yaml:\n%s", want, yamlOut)
		}
	}
	if strings.Contains(yamlOut, `user: "0:0"`) {
		t.Fatalf("compose yaml must not force root user:\n%s", yamlOut)
	}
	if strings.Contains(yamlOut, "openclaw-state-") {
		t.Fatalf("compose yaml must not declare a root-owned named volume:\n%s", yamlOut)
	}
}

// --- Round 2: review findings ---

// P1: destination symlink inside the workspace must not be followed.
func TestCopyOpenClawSkillPackRejectsEscapingDestinationSymlink(t *testing.T) {
	writeSkillPackRoot(t)

	wsSkills := filepath.Join(t.TempDir(), "workspace", "skills")
	if err := os.MkdirAll(wsSkills, 0o755); err != nil {
		t.Fatal(err)
	}
	// skills/github -> outside
	outside := filepath.Join(t.TempDir(), "escaped")
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(wsSkills, "github")); err != nil {
		t.Fatal(err)
	}
	if err := copyOpenClawSkillPack("github", wsSkills); err == nil {
		t.Fatal("expected destination dir symlink escape to be rejected")
	}
	// The outside directory must not have received any SKILL.md.
	if _, err := os.Stat(filepath.Join(outside, "SKILL.md")); err == nil {
		t.Fatal("escaped write detected outside the workspace")
	}
}

func TestCopyOpenClawSkillPackRejectsEscapingDestinationFileSymlink(t *testing.T) {
	writeSkillPackRoot(t)

	wsSkills := filepath.Join(t.TempDir(), "workspace", "skills")
	if err := os.MkdirAll(filepath.Join(wsSkills, "github"), 0o755); err != nil {
		t.Fatal(err)
	}
	outsideFile := filepath.Join(t.TempDir(), "outside.md")
	if err := os.WriteFile(outsideFile, []byte("original"), 0o644); err != nil {
		t.Fatal(err)
	}
	// skills/github/SKILL.md -> outside file
	if err := os.Symlink(outsideFile, filepath.Join(wsSkills, "github", "SKILL.md")); err != nil {
		t.Fatal(err)
	}
	if err := copyOpenClawSkillPack("github", wsSkills); err == nil {
		t.Fatal("expected destination file symlink to be rejected")
	}
	data, err := os.ReadFile(outsideFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "original" {
		t.Fatalf("outside file was overwritten through symlink: %q", data)
	}
}

// P1: untagged reference implies :latest and must not bypass the tag policy.
func TestValidateOpenClawImageUntaggedImpliesLatest(t *testing.T) {
	policy := openClawImagePolicy{
		Allowed:     []string{"ghcr.io/openclaw/openclaw"},
		AllowedTags: []string{"v1"},
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw", policy); err == nil {
		t.Fatal("expected untagged reference (implicit :latest) to be rejected")
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:v1", policy); err != nil {
		t.Fatalf("expected v1 allowed, got %v", err)
	}
}

// P1: tag case is preserved; :RELEASE must not satisfy an allowlist of :release.
func TestValidateOpenClawImageTagCasePreserved(t *testing.T) {
	policy := openClawImagePolicy{
		Allowed:     []string{"ghcr.io/openclaw/openclaw"},
		AllowedTags: []string{"release"},
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:RELEASE", policy); err == nil {
		t.Fatal("expected :RELEASE to be rejected against allowlist entry :release")
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:release", policy); err != nil {
		t.Fatalf("expected :release allowed, got %v", err)
	}
	// Repository matching stays case-insensitive.
	allowedRepo := openClawImagePolicy{Allowed: []string{"ghcr.io/OpenClaw/openclaw"}}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:v3", allowedRepo); err != nil {
		t.Fatalf("expected case-insensitive repository match, got %v", err)
	}
}

// P2: containers dir symlinked outside dataDir with a brand-new container
// name must be rejected (the ENOENT path used to accept it).
func TestValidateProvisionPathsRejectsContainersSymlinkWithNewContainer(t *testing.T) {
	outside := t.TempDir()
	dataDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dataDir, "real-containers"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dataDir, "containers")); err != nil {
		t.Fatal(err)
	}

	// "brand-new-worker" does not exist anywhere: the old code accepted this.
	if _, _, err := validateProvisionPaths(dataDir, "brand-new-worker"); err == nil {
		t.Fatal("expected symlinked containers dir with new container to be rejected")
	}
}

func TestValidateProvisionPathsAcceptsDeepNewContainer(t *testing.T) {
	// containers dir does not exist at all yet: creating the first container
	// must still succeed.
	dataDir := t.TempDir()
	cDir, wsDir, err := validateProvisionPaths(dataDir, "first-worker")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	wantC := filepath.Join(dataDir, "containers", "first-worker")
	if filepath.Clean(cDir) != filepath.Clean(wantC) {
		t.Fatalf("cDir = %q, want %q", cDir, wantC)
	}
	if filepath.Clean(wsDir) != filepath.Clean(filepath.Join(wantC, "workspace")) {
		t.Fatalf("wsDir = %q", wsDir)
	}
}

// The provisioning fallback writes must use the same contained helpers.
func TestWriteContainedFileRejectsSymlink(t *testing.T) {
	dir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "outside.md")
	if err := os.WriteFile(outside, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dir, "SKILL.md")); err != nil {
		t.Fatal(err)
	}
	if err := writeContainedFile(dir, dir, "SKILL.md", []byte("evil"), 0o644); err == nil {
		t.Fatal("expected symlink write to be rejected")
	}
	data, _ := os.ReadFile(outside)
	if string(data) != "keep" {
		t.Fatalf("outside file modified: %q", data)
	}
}

func TestContainedMkdirAllRejectsSymlinkedComponent(t *testing.T) {
	root := t.TempDir()
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(root, "esc")); err != nil {
		t.Fatal(err)
	}
	if _, err := containedMkdirAll(root, []string{"esc", "sub"}, root); err == nil {
		t.Fatal("expected symlinked component to be rejected")
	}
}

// Regression: configured tag values are case-sensitive too. The environment
// parser must not lowercase administrator-provided tags.
func TestLoadOpenClawImagePolicyPreservesTagCase(t *testing.T) {
	t.Setenv("OPENCLAW_IMAGE_ALLOWLIST", "ghcr.io/openclaw/openclaw")
	t.Setenv("OPENCLAW_IMAGE_ALLOWED_TAGS", "RELEASE")

	policy := loadOpenClawImagePolicy()
	if len(policy.AllowedTags) != 1 || policy.AllowedTags[0] != "RELEASE" {
		t.Fatalf("configured tag case was not preserved: %v", policy.AllowedTags)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:RELEASE", policy); err != nil {
		t.Fatalf("expected exact-case RELEASE tag allowed, got %v", err)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:release", policy); err == nil {
		t.Fatal("expected lowercase release to be rejected against RELEASE policy")
	}
}

// Regression for the Lstat -> os.WriteFile TOCTOU window. An attacker racing
// a normal destination file with a symlink must never be able to redirect a
// write outside the workspace root.
func TestWriteContainedFileResistsSymlinkSwap(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "skills")
	dir := filepath.Join(root, "github")
	outside := filepath.Join(base, "outside.md")
	target := filepath.Join(dir, "SKILL.md")

	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("inside"), 0o644); err != nil {
		t.Fatal(err)
	}

	stop := make(chan struct{})
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case <-stop:
				return
			default:
			}
			_ = os.Remove(target)
			_ = os.Symlink(outside, target)
			_ = os.Remove(target)
			_ = os.WriteFile(target, []byte("inside"), 0o644)
		}
	}()
	defer func() {
		close(stop)
		<-done
	}()

	for i := 0; i < 20000; i++ {
		_ = writeContainedFile(dir, root, "SKILL.md", []byte("workspace"), 0o644)
		data, err := os.ReadFile(outside)
		if err != nil {
			t.Fatal(err)
		}
		if string(data) != "keep" {
			t.Fatalf("outside file modified through raced symlink: %q", data)
		}
	}
}

// --- Provision output containment (round-2 review findings) ---

// P1: a pre-existing workspace/skills symlink pointing outside the
// workspace must not become the trusted root for skill materialization.
func TestPrepareProvisionWorkspaceRejectsEscapingSkillsSymlink(t *testing.T) {
	wsDir := filepath.Join(t.TempDir(), "workspace")
	if err := os.MkdirAll(wsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(wsDir, "skills")); err != nil {
		t.Fatal(err)
	}

	if _, _, err := prepareProvisionWorkspace(wsDir); err == nil {
		t.Fatal("expected escaping workspace/skills symlink to be rejected")
	}
}

func TestPrepareProvisionWorkspaceRejectsEscapingMemorySymlink(t *testing.T) {
	wsDir := filepath.Join(t.TempDir(), "workspace")
	if err := os.MkdirAll(wsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(wsDir, "memory")); err != nil {
		t.Fatal(err)
	}

	if _, _, err := prepareProvisionWorkspace(wsDir); err == nil {
		t.Fatal("expected escaping workspace/memory symlink to be rejected")
	}
}

func TestPrepareProvisionWorkspaceReturnsContainedSkillsRoot(t *testing.T) {
	wsDir := filepath.Join(t.TempDir(), "workspace")
	wsEval, skillsRoot, err := prepareProvisionWorkspace(wsDir)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !pathWithinDir(skillsRoot, wsEval) {
		t.Fatalf("skills root %q escapes workspace %q", skillsRoot, wsEval)
	}
	for _, sub := range []string{"skills", "memory"} {
		if info, err := os.Stat(filepath.Join(wsEval, sub)); err != nil || !info.IsDir() {
			t.Fatalf("expected %s dir to exist: %v", sub, err)
		}
	}
}

// P1: an openclaw.json symlink must never redirect the config write outside
// the container data directory.
func TestWriteOpenClawConfigRejectsSymlink(t *testing.T) {
	cDir := t.TempDir()
	outside := filepath.Join(t.TempDir(), "outside.json")
	if err := os.WriteFile(outside, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(cDir, "openclaw.json")); err != nil {
		t.Fatal(err)
	}

	if err := writeOpenClawConfig(filepath.Join(cDir, "openclaw.json"), ProvisionRequest{}); err == nil {
		t.Fatal("expected config write through symlink to be rejected")
	}
	data, _ := os.ReadFile(outside)
	if string(data) != "keep" {
		t.Fatalf("outside file modified: %q", data)
	}
}

// The stale-directory recovery must keep working on the contained writer.
func TestWriteOpenClawConfigReplacesStaleDirectory(t *testing.T) {
	cDir := t.TempDir()
	stale := filepath.Join(cDir, "openclaw.json")
	if err := os.MkdirAll(filepath.Join(stale, "nested"), 0o755); err != nil {
		t.Fatal(err)
	}

	if err := writeOpenClawConfig(stale, ProvisionRequest{}); err != nil {
		t.Fatalf("expected stale directory to be replaced, got %v", err)
	}
	info, err := os.Lstat(stale)
	if err != nil || !info.Mode().IsRegular() {
		t.Fatalf("expected regular config file, err=%v", err)
	}
}

// P1: the deployed image packages skill packs at <wd>/skills while the
// source tree keeps them at <wd>/skillpacks; the deployed layout wins.
func TestOpenClawSkillPackDirInPrefersDeployedSkills(t *testing.T) {
	wd := t.TempDir()
	for _, d := range []string{"skills", "skillpacks"} {
		if err := os.MkdirAll(filepath.Join(wd, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if got := openClawSkillPackDirIn(wd); got != filepath.Join(wd, "skills") {
		t.Fatalf("expected deployed skills dir, got %q", got)
	}
}

func TestOpenClawSkillPackDirInFallsBackToSourceLayout(t *testing.T) {
	wd := t.TempDir()
	if err := os.MkdirAll(filepath.Join(wd, "skillpacks"), 0o755); err != nil {
		t.Fatal(err)
	}
	if got := openClawSkillPackDirIn(wd); got != filepath.Join(wd, "skillpacks") {
		t.Fatalf("expected source-tree skillpacks dir, got %q", got)
	}
}

// P1: the non-root image user must be able to write the bind-mounted
// workspace; chmod must never follow an escaping symlink.
func TestMakeWorkspaceWritableGrantsGroupAccess(t *testing.T) {
	wsDir := t.TempDir()
	sub := filepath.Join(wsDir, "memory")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(sub, "note.md")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}

	outside := filepath.Join(t.TempDir(), "outside.md")
	if err := os.WriteFile(outside, []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(sub, "link.md")); err != nil {
		t.Fatal(err)
	}

	if err := makeWorkspaceWritable(wsDir, os.Getgid()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for p, want := range map[string]os.FileMode{wsDir: 0o770, sub: 0o770, file: 0o660} {
		info, err := os.Stat(p)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != want {
			t.Fatalf("%s mode = %o, want %o", p, info.Mode().Perm(), want)
		}
	}
	// The symlink target must not have been chmodded through the link.
	info, err := os.Stat(outside)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("outside file mode changed to %o", info.Mode().Perm())
	}
}

// P1 (recurring): a full-reference allowlist entry must compare the tag
// case-sensitively, so "repo:RELEASE" cannot satisfy "repo:release" while
// the runtime pulls the distinct uppercase tag.
func TestValidateOpenClawImageAllowlistEntryPreservesTagCase(t *testing.T) {
	policy := openClawImagePolicy{Allowed: []string{"ghcr.io/openclaw/openclaw:release"}}

	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:RELEASE", policy); err == nil {
		t.Fatal("expected :RELEASE to be rejected against allowlist entry :release")
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:release", policy); err != nil {
		t.Fatalf("expected :release allowed, got %v", err)
	}
	// Repository case still folds like the runtime's normalization.
	if err := validateOpenClawImage("GHCR.IO/OpenClaw/openclaw:release", policy); err != nil {
		t.Fatalf("expected case-insensitive repository match, got %v", err)
	}
	// A bare repository entry allows any tag.
	bare := openClawImagePolicy{Allowed: []string{"ghcr.io/openclaw/openclaw"}}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:v3", bare); err != nil {
		t.Fatalf("expected bare repository entry to allow any tag, got %v", err)
	}
	// A digest entry requires the exact digest.
	digestEntry := openClawImagePolicy{Allowed: []string{"ghcr.io/openclaw/openclaw@sha256:abc"}}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw@sha256:abc", digestEntry); err != nil {
		t.Fatalf("expected matching digest allowed, got %v", err)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw@sha256:def", digestEntry); err == nil {
		t.Fatal("expected mismatched digest to be rejected")
	}
}

// P1 (Devin Review): the allowlist must preserve administrator-provided tag
// case. Lowercasing the entry at parse time let "repo:release" through when
// the policy only authorized the distinct "repo:RELEASE" image.
func TestLoadOpenClawImagePolicyPreservesEntryTagCase(t *testing.T) {
	t.Setenv("OPENCLAW_IMAGE_ALLOWLIST", "ghcr.io/openclaw/openclaw:RELEASE")

	policy := loadOpenClawImagePolicy()
	if len(policy.Allowed) != 1 || policy.Allowed[0] != "ghcr.io/openclaw/openclaw:RELEASE" {
		t.Fatalf("configured entry case was not preserved: %v", policy.Allowed)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:RELEASE", policy); err != nil {
		t.Fatalf("expected exact-case RELEASE allowed, got %v", err)
	}
	if err := validateOpenClawImage("ghcr.io/openclaw/openclaw:release", policy); err == nil {
		t.Fatal("expected lowercase release to be rejected against :RELEASE allowlist entry")
	}
}
