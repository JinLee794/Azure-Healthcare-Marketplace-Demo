import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

export interface Skill {
  name: string;
  description: string;
  triggers: string[];
  content: string;
  references: Map<string, string>;
}

export class HealthcareSkillLoader {
  private skills: Map<string, Skill> = new Map();
  private skillsPath: string;

  constructor(private context: vscode.ExtensionContext) {
    // Skills can be loaded from extension or workspace
    this.skillsPath = path.join(context.extensionPath, 'skills');
    this.loadSkills();
  }

  private async loadSkills(): Promise<void> {
    // Load skills from workspace if available
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (workspaceFolders) {
      for (const folder of workspaceFolders) {
        const skillsDir = path.join(folder.uri.fsPath, '.github', 'skills');
        if (fs.existsSync(skillsDir)) {
          await this.loadSkillsFromDirectory(skillsDir);
        }
      }
    }

    // Load built-in skills
    if (fs.existsSync(this.skillsPath)) {
      await this.loadSkillsFromDirectory(this.skillsPath);
    }

    console.log(`Loaded ${this.skills.size} healthcare skills`);
  }

  private async loadSkillsFromDirectory(dir: string): Promise<void> {
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });

      for (const entry of entries) {
        if (entry.isDirectory()) {
          const skillPath = path.join(dir, entry.name, 'SKILL.md');
          if (fs.existsSync(skillPath)) {
            await this.loadSkill(entry.name, skillPath);
          }
        }
      }
    } catch (error) {
      console.error(`Error loading skills from ${dir}:`, error);
    }
  }

  private async loadSkill(name: string, skillPath: string): Promise<void> {
    try {
      const content = fs.readFileSync(skillPath, 'utf-8');
      const { frontmatter, body } = this.parseFrontmatter(content);

      const skill: Skill = {
        name: frontmatter.name || name,
        description: frontmatter.description || '',
        triggers: frontmatter.triggers || [],
        content: body,
        references: new Map(),
      };

      // Load references
      const refsDir = path.join(path.dirname(skillPath), 'references');
      if (fs.existsSync(refsDir)) {
        const refs = fs.readdirSync(refsDir);
        for (const ref of refs) {
          if (ref.endsWith('.md')) {
            const refContent = fs.readFileSync(path.join(refsDir, ref), 'utf-8');
            skill.references.set(ref.replace('.md', ''), refContent);
          }
        }
      }

      this.skills.set(name, skill);
    } catch (error) {
      console.error(`Error loading skill ${name}:`, error);
    }
  }

  private parseFrontmatter(content: string): { frontmatter: Record<string, unknown>; body: string } {
    const frontmatterRegex = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/;
    const match = content.match(frontmatterRegex);

    if (!match) {
      return { frontmatter: {}, body: content };
    }

    try {
      // Simple YAML-like parsing (in production, use a proper YAML parser)
      const frontmatter: Record<string, unknown> = {};
      const lines = match[1].split('\n');
      
      for (const line of lines) {
        const colonIndex = line.indexOf(':');
        if (colonIndex > 0) {
          const key = line.substring(0, colonIndex).trim();
          let value: unknown = line.substring(colonIndex + 1).trim();
          
          // Handle arrays
          if (value === '') {
            // Check for array on next lines
            const arrayItems: string[] = [];
            // This is simplified - in production use proper YAML
            frontmatter[key] = arrayItems;
          } else {
            // Remove quotes
            if (typeof value === 'string') {
              value = value.replace(/^["']|["']$/g, '');
            }
            frontmatter[key] = value;
          }
        }
      }

      return { frontmatter, body: match[2] };
    } catch {
      return { frontmatter: {}, body: content };
    }
  }

  public getSkill(name: string): Skill | undefined {
    return this.skills.get(name);
  }

  public findSkillsForQuery(query: string): Skill[] {
    const queryLower = query.toLowerCase();
    const matches: Skill[] = [];

    for (const skill of this.skills.values()) {
      // Check triggers
      const triggerMatch = skill.triggers.some(
        trigger => queryLower.includes(trigger.toLowerCase())
      );

      // Check name and description
      const nameMatch = skill.name.toLowerCase().includes(queryLower) ||
        queryLower.includes(skill.name.toLowerCase());
      const descMatch = skill.description.toLowerCase().includes(queryLower);

      if (triggerMatch || nameMatch || descMatch) {
        matches.push(skill);
      }
    }

    return matches;
  }

  public getAllSkills(): Skill[] {
    return Array.from(this.skills.values());
  }

  public getSkillContext(skillName: string): string {
    const skill = this.skills.get(skillName);
    if (!skill) {
      return '';
    }

    let context = `## ${skill.name}\n\n${skill.content}`;

    // Include references
    for (const [refName, refContent] of skill.references) {
      context += `\n\n### Reference: ${refName}\n\n${refContent}`;
    }

    return context;
  }
}
