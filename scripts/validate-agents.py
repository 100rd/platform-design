#!/usr/bin/env python3
"""
Custom Agent Validator for GitHub Copilot Custom Agents (.github/agents/*.agent.md)
"""
import os
import re
import sys

def parse_frontmatter(content: str):
    """
    Parses simple YAML frontmatter.
    Returns a dictionary of key-value pairs and the remaining body.
    """
    # Look for frontmatter enclosed by ---
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n", content, re.DOTALL)
    if not match:
        return None, content
    
    frontmatter_str = match.group(1)
    body = content[match.end():]
    
    metadata = {}
    for line in frontmatter_str.split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            raise ValueError(f"Invalid frontmatter syntax (missing colon): '{line}'")
        
        key, val = line.split(":", 1)
        key = key.strip()
        val = val.strip()
        
        # Simple array parsing: ["*"] or [tool1, tool2]
        if val.startswith("[") and val.endswith("]"):
            val_content = val[1:-1].strip()
            if not val_content:
                val = []
            else:
                val = [item.strip().strip('"').strip("'") for item in val_content.split(",")]
        else:
            # Strip quotes if present
            if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
                
        metadata[key] = val
        
    return metadata, body

def validate_agent_file(filepath: str) -> list:
    errors = []
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except Exception as e:
        return [f"Failed to read file: {e}"]
        
    try:
        metadata, body = parse_frontmatter(content)
    except Exception as e:
        return [f"Frontmatter parsing error: {e}"]
        
    if metadata is None:
        return ["File must start with YAML frontmatter bounded by '---'"]
        
    # Check required fields
    if "name" not in metadata:
        errors.append("Missing required field 'name' in frontmatter")
    else:
        name = metadata["name"]
        if not isinstance(name, str) or not re.match(r"^[a-zA-Z0-9-_]+$", name):
            errors.append(f"Invalid agent name '{name}' (must contain only alphanumeric characters, hyphens, and underscores)")
            
    if "description" not in metadata:
        errors.append("Missing required field 'description' in frontmatter")
    else:
        desc = metadata["description"]
        if not isinstance(desc, str) or len(desc.strip()) < 10:
            errors.append("Description must be a non-empty string of at least 10 characters")
            
    if "tools" in metadata:
        tools = metadata["tools"]
        if not isinstance(tools, list):
            errors.append("Tools field must be a list (e.g. ['*'] or ['tool-1', 'tool-2'])")
            
    if not body.strip():
        errors.append("Agent instructions body must not be empty")
        
    return errors

def main():
    agents_dir = "agents" if os.path.exists("agents") else os.path.join(".github", "agents")
    if not os.path.exists(agents_dir):
        print(f"❌ Agents directory not found: agents/ or .github/agents/")
        sys.exit(1)
        
    files = [f for f in os.listdir(agents_dir) if f.endswith(".agent.md")]
    if not files:
        print(f"⚠️ No agent files found in {agents_dir}")
        sys.exit(0)
        
    all_passed = True
    print(f"🔍 Validating {len(files)} agent files...")
    
    for filename in files:
        filepath = os.path.join(agents_dir, filename)
        errors = validate_agent_file(filepath)
        if errors:
            print(f"❌ {filepath} failed validation:")
            for err in errors:
                print(f"   - {err}")
            all_passed = False
        else:
            print(f"✅ {filepath} is valid")
            
    if not all_passed:
        print("\n❌ Some agent files failed validation!")
        sys.exit(1)
        
    print("\n🎉 All agents are valid!")
    sys.exit(0)

if __name__ == "__main__":
    main()
