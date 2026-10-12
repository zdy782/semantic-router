package handlers

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// --- Skills ---

var openClawSkillIDPattern = regexp.MustCompile(`^[a-z0-9]+(?:[-_][a-z0-9]+)*$`)

func validateOpenClawSkillIDs(ids []string, catalog []SkillTemplate) error {
	allowed := make(map[string]struct{}, len(catalog))
	for _, skill := range catalog {
		allowed[skill.ID] = struct{}{}
	}
	for _, id := range ids {
		if !openClawSkillIDPattern.MatchString(id) {
			return fmt.Errorf("invalid skill ID %q", id)
		}
		if _, ok := allowed[id]; !ok {
			return fmt.Errorf("unknown skill ID %q", id)
		}
	}
	return nil
}

func (h *OpenClawHandler) SkillsHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		skills, err := h.loadSkills()
		if err != nil {
			log.Printf("Warning: failed to load skills config: %v", err)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte("[]"))
			return
		}
		// Only offer skills that have a server-side pack: provisioning
		// cannot materialize catalog entries without one, so listing them
		// would let users select skills that then fail with HTTP 400.
		provisionable := skills[:0]
		for _, s := range skills {
			if _, _, packErr := resolveOpenClawSkillPack(s.ID); packErr == nil {
				provisionable = append(provisionable, s)
			}
		}
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(provisionable); err != nil {
			log.Printf("openclaw: skills encode error: %v", err)
		}
	}
}

func (h *OpenClawHandler) loadSkills() ([]SkillTemplate, error) {
	candidates := make([]string, 0, 12)
	if p := strings.TrimSpace(os.Getenv("OPENCLAW_SKILLS_PATH")); p != "" {
		candidates = append(candidates, p)
	}

	candidates = append(candidates,
		filepath.Join(h.dataDir, "skills.json"),
		filepath.Join(h.dataDir, "..", "..", "config", "openclaw-skills.json"),
		"/app/config/openclaw-skills.json",
		"/app/dashboard/backend/config/openclaw-skills.json",
		"./config/openclaw-skills.json",
	)

	if wd, err := os.Getwd(); err == nil {
		candidates = append(candidates, filepath.Join(wd, "config", "openclaw-skills.json"))
	}
	if exe, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exe)
		candidates = append(candidates,
			filepath.Join(exeDir, "config", "openclaw-skills.json"),
			filepath.Join(exeDir, "..", "config", "openclaw-skills.json"),
		)
	}

	seen := make(map[string]struct{}, len(candidates))
	for _, rawPath := range candidates {
		configPath := strings.TrimSpace(rawPath)
		if configPath == "" {
			continue
		}
		cleanPath := filepath.Clean(configPath)
		if _, ok := seen[cleanPath]; ok {
			continue
		}
		seen[cleanPath] = struct{}{}

		data, err := os.ReadFile(configPath)
		if err != nil {
			continue
		}
		var skills []SkillTemplate
		if err := json.Unmarshal(data, &skills); err != nil {
			return nil, fmt.Errorf("invalid %s: %w", configPath, err)
		}
		log.Printf("openclaw: loaded %d skills from %s", len(skills), configPath)
		return skills, nil
	}
	return []SkillTemplate{}, nil
}
