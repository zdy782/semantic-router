package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// rewriteLoopbackHost replaces 127.0.0.1 / localhost in a URL with the given
// container name so that inter-container traffic uses Docker DNS instead of
// loopback (which is unreachable across containers in bridge networks).
func rewriteLoopbackHost(rawURL, containerName string) string {
	if rawURL == "" || containerName == "" {
		return rawURL
	}
	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	host := u.Hostname()
	if host != "127.0.0.1" && host != "localhost" && host != "0.0.0.0" {
		return rawURL
	}
	port := u.Port()
	if port != "" {
		u.Host = containerName + ":" + port
	} else {
		u.Host = containerName
	}
	return u.String()
}

func appendOpenClawV1Path(rawURL string) string {
	if rawURL == "" {
		return rawURL
	}

	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}

	trimmedPath := strings.TrimRight(u.Path, "/")
	if trimmedPath == "/v1" {
		u.Path = "/v1"
		return u.String()
	}
	if trimmedPath == "" {
		u.Path = "/v1"
		return u.String()
	}

	u.Path = trimmedPath + "/v1"
	return u.String()
}

func openClawModelGatewayContainerName() string {
	if candidate := strings.TrimSpace(os.Getenv("OPENCLAW_MODEL_GATEWAY_CONTAINER_NAME")); candidate != "" {
		return candidate
	}
	if candidate := openClawContainerHostFromURL(strings.TrimSpace(os.Getenv("TARGET_ENVOY_URL"))); candidate != "" {
		return candidate
	}
	if candidate := strings.TrimSpace(os.Getenv(envoyContainerNameEnv)); candidate != "" {
		return candidate
	}
	if candidate := strings.TrimSpace(os.Getenv("OPENCLAW_DASHBOARD_CONTAINER_NAME")); candidate != "" {
		return candidate
	}
	return defaultRouterContainerName
}

func openClawContainerHostFromURL(rawURL string) string {
	if rawURL == "" {
		return ""
	}

	u, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}

	host := strings.TrimSpace(u.Hostname())
	if host == "" || host == "127.0.0.1" || host == "localhost" || host == "0.0.0.0" {
		return ""
	}
	return host
}

// --- Helpers ---

func sanitizeContainerName(raw string) string {
	cleaned := strings.ToLower(strings.TrimSpace(raw))
	cleaned = containerNameInvalidChars.ReplaceAllString(cleaned, "-")
	cleaned = strings.Trim(cleaned, "._-")
	if cleaned == "" {
		return ""
	}

	// Keep names bounded and still docker-friendly.
	const maxLen = 63
	if len(cleaned) > maxLen {
		cleaned = strings.Trim(cleaned[:maxLen], "._-")
	}
	if cleaned == "" {
		return ""
	}

	first := cleaned[0]
	if (first < 'a' || first > 'z') && (first < '0' || first > '9') {
		cleaned = "oc-" + cleaned
	}
	return cleaned
}

func sanitizeTeamID(raw string) string {
	return sanitizeContainerName(raw)
}

func sanitizeRoomID(raw string) string {
	return sanitizeContainerName(raw)
}

func normalizeRoleKind(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "leader":
		return "leader"
	default:
		return "worker"
	}
}

func deriveContainerName(requested, identityName string) string {
	if name := sanitizeContainerName(requested); name != "" {
		return name
	}
	if name := sanitizeContainerName(identityName); name != "" {
		return name
	}
	return "openclaw-vllm-sr"
}

func readIdentitySnapshot(dataDir string) identitySnapshot {
	wsDir := filepath.Join(dataDir, "workspace")
	snapshot := identitySnapshot{}

	identityContent, err := os.ReadFile(filepath.Join(wsDir, "IDENTITY.md"))
	if err == nil {
		for _, raw := range strings.Split(string(identityContent), "\n") {
			line := strings.TrimSpace(raw)
			switch {
			case strings.HasPrefix(line, "- **Name:**"):
				snapshot.Name = strings.TrimSpace(strings.TrimPrefix(line, "- **Name:**"))
			case strings.HasPrefix(line, "- **Creature:**"):
				snapshot.Role = strings.TrimSpace(strings.TrimPrefix(line, "- **Creature:**"))
			case strings.HasPrefix(line, "- **Vibe:**"):
				snapshot.Vibe = strings.TrimSpace(strings.TrimPrefix(line, "- **Vibe:**"))
			case strings.HasPrefix(line, "- **Emoji:**"):
				snapshot.Emoji = strings.TrimSpace(strings.TrimPrefix(line, "- **Emoji:**"))
			}
		}
	}

	soulContent, err := os.ReadFile(filepath.Join(wsDir, "SOUL.md"))
	if err == nil {
		lines := strings.Split(string(soulContent), "\n")
		capture := false
		var truths []string
		for _, raw := range lines {
			line := strings.TrimSpace(raw)
			if strings.HasPrefix(line, "## ") {
				if line == "## Core Truths" {
					capture = true
					continue
				}
				if capture {
					break
				}
			}
			if capture && line != "" {
				truths = append(truths, line)
			}
		}
		if len(truths) > 0 {
			snapshot.Principles = strings.Join(truths, " ")
		}
	}

	return snapshot
}

func writeJSONError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(map[string]string{"error": msg}); err != nil {
		log.Printf("openclaw: error encode error: %v", err)
	}
}

func generateToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "changeme-" + fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

// writeIdentityFiles writes the identity documents inside the workspace.
// All writes go through the contained helpers so a pre-existing symlink at
// the destination can never redirect a write outside the workspace.
func writeIdentityFiles(wsDir string, id IdentityConfig) error {
	wsEval, err := resolveExistingDir(wsDir)
	if err != nil {
		return err
	}
	var soulParts []string
	soulParts = append(soulParts, "# SOUL.md - Who You Are\n")
	if id.Name != "" || id.Role != "" {
		soulParts = append(soulParts, "## Core Identity\n")
		if id.Name != "" && id.Role != "" {
			soulParts = append(soulParts, fmt.Sprintf("You are **%s**, %s.\n", id.Name, id.Role))
		} else if id.Name != "" {
			soulParts = append(soulParts, fmt.Sprintf("You are **%s**.\n", id.Name))
		}
	}
	if id.Principles != "" {
		soulParts = append(soulParts, "## Core Truths\n")
		soulParts = append(soulParts, id.Principles+"\n")
	}
	if id.Boundaries != "" {
		soulParts = append(soulParts, "## Boundaries\n")
		soulParts = append(soulParts, id.Boundaries+"\n")
	}
	if id.Vibe != "" {
		soulParts = append(soulParts, "## Vibe\n")
		soulParts = append(soulParts, id.Vibe+"\n")
	}
	if err := writeContainedFile(wsEval, wsEval, "SOUL.md", []byte(strings.Join(soulParts, "\n")), 0o644); err != nil {
		return err
	}

	var idParts []string
	idParts = append(idParts, "# IDENTITY.md - Who Am I?\n")
	if id.Name != "" {
		idParts = append(idParts, fmt.Sprintf("- **Name:** %s", id.Name))
	}
	if id.Role != "" {
		idParts = append(idParts, fmt.Sprintf("- **Creature:** %s", id.Role))
	}
	if id.Vibe != "" {
		idParts = append(idParts, fmt.Sprintf("- **Vibe:** %s", id.Vibe))
	}
	if id.Emoji != "" {
		idParts = append(idParts, fmt.Sprintf("- **Emoji:** %s", id.Emoji))
	}
	if err := writeContainedFile(wsEval, wsEval, "IDENTITY.md", []byte(strings.Join(idParts, "\n")+"\n"), 0o644); err != nil {
		return err
	}

	var userParts []string
	userParts = append(userParts, "# USER.md - About Your Human\n")
	if id.UserName != "" {
		userParts = append(userParts, fmt.Sprintf("- **Name:** %s", id.UserName))
	}
	if id.UserNotes != "" {
		userParts = append(userParts, fmt.Sprintf("- **Notes:** %s", id.UserNotes))
	}
	return writeContainedFile(wsEval, wsEval, "USER.md", []byte(strings.Join(userParts, "\n")+"\n"), 0o644)
}

func buildOpenClawModelProviderConfig(req ProvisionRequest) map[string]interface{} {
	return map[string]interface{}{
		"baseUrl": req.Container.ModelBaseURL,
		"apiKey":  req.Container.ModelAPIKey,
		"api":     "openai-completions",
		"headers": map[string]string{"x-authz-user-id": "openclaw-demo-user"},
		"models": []map[string]interface{}{
			{
				"id": req.Container.ModelName, "name": "SR Routed Model",
				"reasoning": false, "input": []string{"text", "image"},
				"cost":          map[string]interface{}{"input": 0.15, "output": 0.6, "cacheRead": 0, "cacheWrite": 0},
				"contextWindow": normalizeOpenClawModelContextWindow(req.Container.ModelContextWindow),
				"compat":        map[string]string{"maxTokensField": "max_tokens"},
			},
		},
	}
}

func writeOpenClawConfig(path string, req ProvisionRequest) error {
	// Writes go through an os.Root anchored at the resolved container data
	// directory so a pre-existing symlink at the config path can never
	// redirect the write outside it.
	dirEval, err := resolveExistingDir(filepath.Dir(path))
	if err != nil {
		return fmt.Errorf("failed to resolve config dir: %w", err)
	}
	name := filepath.Base(path)

	rootFS, err := os.OpenRoot(dirEval)
	if err != nil {
		return fmt.Errorf("failed to open config dir: %w", err)
	}
	defer func() { _ = rootFS.Close() }()

	// Recover from stale state where a previous bad bind mount caused
	// openclaw.json to be created as a directory on host.
	info, statErr := rootFS.Lstat(name)
	switch {
	case statErr == nil && info.IsDir():
		if err := rootFS.RemoveAll(name); err != nil {
			return fmt.Errorf("failed to replace config directory %s with file: %w", name, err)
		}
	case statErr == nil && info.Mode()&os.ModeSymlink != 0:
		return fmt.Errorf("refusing to write config through symlink %s", name)
	case statErr == nil && !info.Mode().IsRegular():
		return fmt.Errorf("refusing to overwrite non-regular config %s", name)
	case statErr != nil && !os.IsNotExist(statErr):
		return fmt.Errorf("failed to stat config path %s: %w", name, statErr)
	}

	cfg := map[string]interface{}{
		"models": map[string]interface{}{
			"providers": map[string]interface{}{
				"vllm": buildOpenClawModelProviderConfig(req),
			},
		},
		"agents": map[string]interface{}{
			"defaults": map[string]interface{}{
				"model":      map[string]string{"primary": "vllm/" + req.Container.ModelName},
				"workspace":  "/workspace",
				"compaction": map[string]string{"mode": "safeguard"},
			},
			"list": []map[string]interface{}{
				{"id": openClawPrimaryAgentID, "default": true, "name": "vLLM-SR Powered Agent", "workspace": "/workspace"},
			},
		},
		"commands": map[string]interface{}{"native": "auto", "nativeSkills": "auto", "restart": true},
		"gateway": map[string]interface{}{
			"port": req.Container.GatewayPort,
			"auth": map[string]string{"mode": "token", "token": req.Container.AuthToken},
			"http": map[string]interface{}{
				"endpoints": map[string]interface{}{
					"chatCompletions": map[string]interface{}{"enabled": true},
					"responses":       map[string]interface{}{"enabled": true},
				},
			},
			"controlUi": map[string]interface{}{
				"dangerouslyDisableDeviceAuth": true,
				"allowInsecureAuth":            true,
				"allowedOrigins":               []string{"*"},
			},
		},
	}
	memoryBackend := strings.ToLower(strings.TrimSpace(req.Container.MemoryBackend))
	if memoryBackend == "" {
		memoryBackend = "local"
	}

	// OpenClaw v2 memory schema:
	// - memory.backend accepts "builtin" or "qmd"
	// - remote embedding config lives under agents.defaults.memorySearch
	switch memoryBackend {
	case "qmd":
		cfg["memory"] = map[string]interface{}{"backend": "qmd"}
	case "remote":
		cfg["memory"] = map[string]interface{}{"backend": "builtin"}

		memorySearch := map[string]interface{}{
			"enabled":  true,
			"provider": "openai",
		}

		remote := map[string]interface{}{}
		if baseURL := strings.TrimSpace(req.Container.MemoryBaseURL); baseURL != "" {
			remote["baseUrl"] = baseURL
		}
		if apiKey := strings.TrimSpace(req.Container.ModelAPIKey); apiKey != "" && apiKey != "not-needed" {
			remote["apiKey"] = apiKey
		}
		if len(remote) > 0 {
			memorySearch["remote"] = remote
		}

		agentsCfg, _ := cfg["agents"].(map[string]interface{})
		defaultsCfg, _ := agentsCfg["defaults"].(map[string]interface{})
		defaultsCfg["memorySearch"] = memorySearch
	default:
		// "local" (or unknown values) falls back to builtin memory without
		// remote embedding configuration.
		cfg["memory"] = map[string]interface{}{"backend": "builtin"}
	}
	if req.Container.BrowserEnabled {
		cfg["browser"] = map[string]interface{}{"enabled": true, "headless": true, "noSandbox": true}
	}
	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return rootFS.WriteFile(name, data, 0o644)
}

// legacyStateMigrationMarker is written into the state dir once a legacy
// named volume has been fully migrated. Its absence means migration has not
// completed — a partially copied tree is retried instead of skipped.
const legacyStateMigrationMarker = ".openclaw-state-migrated"

// migrateLegacyStateVolume copies content from the legacy named volume
// "openclaw-state-<name>" (used by provisioning versions before /state
// became a bind mount) into stateDir, then removes the volume. It runs
// only when the volume exists and no completion marker is present, so an
// interrupted copy is retried on the next provision instead of stranding
// sessions. The copy runs in a one-shot root helper container because
// volume content is owned by the privileged user those older versions ran
// as. Anything that is not a directory or regular file (symlinks, device
// nodes, fifos) is deleted after the copy so worker-controlled special
// entries cannot be relabelled into something the gateway would follow
// or open, and the copied files are group-relabelled for the non-root
// gateway.
func (h *OpenClawHandler) migrateLegacyStateVolume(image, containerName, stateDir string, gid int) error {
	volume := "openclaw-state-" + containerName
	if out, err := h.containerCombinedOutput("volume", "inspect", volume); err != nil || len(out) == 0 {
		return nil // no legacy volume to migrate
	}
	if _, err := os.Lstat(filepath.Join(stateDir, legacyStateMigrationMarker)); err == nil {
		// Already migrated — drop the leftover volume and move on.
		if err := h.containerRun("volume", "rm", volume); err != nil {
			log.Printf("openclaw: warning: could not remove legacy state volume %s: %v", volume, err)
		}
		return nil
	}
	script := fmt.Sprintf(
		"cp -a /from/. /to/ && find /to -mindepth 1 ! -type d ! -type f -delete && "+
			"chgrp -R %d /to && chmod -R g+rwX,o-rwx /to && touch /to/%s",
		gid, legacyStateMigrationMarker,
	)
	if out, err := h.containerCombinedOutput(
		"run", "--rm", "--user", "0:0",
		"-v", volume+":/from:ro",
		"-v", stateDir+":/to",
		image, "sh", "-c", script,
	); err != nil {
		return fmt.Errorf("copying state from legacy volume %s: %w: %s", volume, err, strings.TrimSpace(string(out)))
	}
	// Migrated successfully: drop the legacy volume so future reprovisions
	// use only the bind mount.
	if err := h.containerRun("volume", "rm", volume); err != nil {
		log.Printf("openclaw: warning: could not remove legacy state volume %s: %v", volume, err)
	}
	return nil
}

func generateDockerRunCmd(runtime string, req ProvisionRequest, dataDir string, gid int) string {
	healthCmd := fmt.Sprintf(
		`node -e "fetch('http://127.0.0.1:%d/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"`,
		req.Container.GatewayPort,
	)
	return fmt.Sprintf(`%s run -d \
  --name %s \
  --network %s \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --group-add %d \
  --health-cmd '%s' \
  --health-interval 30s \
  --health-timeout 5s \
  --health-start-period 15s \
  --health-retries 3 \
  -v %s/workspace:/workspace \
  -v %s/openclaw.json:/config/openclaw.json:ro \
  -v %s/state:/state \
  -e OPENCLAW_CONFIG_PATH=/config/openclaw.json \
  -e OPENCLAW_STATE_DIR=/state \
  %s \
  node openclaw.mjs gateway --allow-unconfigured --bind lan`,
		runtime, req.Container.ContainerName, req.Container.NetworkMode, gid, healthCmd,
		dataDir, dataDir, dataDir, req.Container.BaseImage)
}

func generateComposeYAML(req ProvisionRequest, dataDir string, gid int) string {
	networkMode := req.Container.NetworkMode

	// For bridge network names (not "host" or "container:xxx"), use the networks syntax.
	if networkMode != "" && networkMode != "host" && !strings.HasPrefix(networkMode, "container:") {
		return fmt.Sprintf(`services:
  openclaw:
    image: %s
    container_name: %s
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m
    group_add:
      - "%d"
    networks:
      - %s
    volumes:
      - %s/workspace:/workspace
      - %s/openclaw.json:/config/openclaw.json:ro
      - %s/state:/state
    environment:
      OPENCLAW_CONFIG_PATH: /config/openclaw.json
      OPENCLAW_STATE_DIR: /state
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:%d/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3
    command: ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
    restart: unless-stopped

networks:
  %s:
    external: true
`, req.Container.BaseImage, req.Container.ContainerName,
			gid, networkMode,
			dataDir, dataDir, dataDir,
			req.Container.GatewayPort,
			networkMode)
	}

	return fmt.Sprintf(`services:
  openclaw:
    image: %s
    container_name: %s
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=64m
    group_add:
      - "%d"
    network_mode: %s
    volumes:
      - %s/workspace:/workspace
      - %s/openclaw.json:/config/openclaw.json:ro
      - %s/state:/state
    environment:
      OPENCLAW_CONFIG_PATH: /config/openclaw.json
      OPENCLAW_STATE_DIR: /state
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:%d/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3
    command: ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
    restart: unless-stopped
`, req.Container.BaseImage, req.Container.ContainerName,
		gid, networkMode,
		dataDir, dataDir, dataDir,
		req.Container.GatewayPort)
}

func agentsMdContent() string {
	return `# AGENTS.md - Your Workspace

This folder is home. Treat it that way.

## Every Session

Before doing anything else:

1. Read ` + "`SOUL.md`" + ` — this is who you are
2. Read ` + "`IDENTITY.md`" + ` — your profile, vibe, and persona details
3. Read ` + "`USER.md`" + ` — this is who you're helping
4. Read ` + "`memory/`" + ` for recent context

## Memory

You wake up fresh each session. These files are your continuity:

- **Daily notes:** ` + "`memory/YYYY-MM-DD.md`" + ` — raw logs of what happened
- **Skills:** ` + "`skills/*/SKILL.md`" + ` — your specialized abilities

## Safety

- Don't exfiltrate private data
- Don't run destructive commands without asking
- When in doubt, ask

## Tools

Skills provide your tools. When you need one, check its SKILL.md.
`
}
