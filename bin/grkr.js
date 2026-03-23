#!/usr/bin/env node

const { program } = require('commander');
const { execSync } = require('child_process');

program
  .name('grkr')
  .description('AI-powered tool to implement GitHub issues using opencode')
  .option('--issue <number>', 'GitHub issue number to implement')
  .parse(process.argv);

const options = program.opts();

if (!options.issue) {
  console.error('Error: --issue <number> is required');
  process.exit(1);
}

console.log(`Implementing issue #${options.issue}...`);

try {
  // Fetch issue using gh CLI
  const issueData = execSync(`gh issue view ${options.issue} --json title,body,url`, { encoding: 'utf8' });
  const issue = JSON.parse(issueData);
  
  console.log(`Found issue: ${issue.title}`);
  
  // Create branch
  const branchName = `issue-${options.issue}`;
  execSync(`git checkout -b ${branchName}`, { stdio: 'inherit' });
  
  // Prepare prompt for opencode
  const prompt = `Implement the following GitHub issue in this repository:\n\nTitle: ${issue.title}\n\nDescription:\n${issue.body}\n\nFollow the existing code conventions and make the changes necessary.`;
  
  console.log('Running opencode with the issue description...');
  
  const opencodePath = '/Users/stepango/.opencode/bin/opencode';
  
  try {
    // Run opencode - in practice this might need to be non-interactive or use expect
    // For now we print the prompt and note that opencode should be run with it
    console.log('\n--- PROMPT FOR OPCODE ---');
    console.log(prompt);
    console.log('------------------------\n');
    
    console.log('Please run the following manually for now:');
    console.log(`${opencodePath} "${prompt.replace(/"/g, '\\"')}"`);
  } catch (e) {
    console.log('Could not run opencode automatically.');
  }
  
  console.log(`✅ Branch created: ${branchName}`);
  console.log('After implementing changes with opencode, run:');
  console.log(`  git add . && git commit -m "feat: implement #${options.issue} - ${issue.title}"`);
  console.log(`  gh pr create --title "Implement #${options.issue}: ${issue.title}" --body "Closes #${options.issue}\\n\\nImplemented via grkr + opencode CLI"`);
  
  console.log(`✅ Successfully prepared for issue #${options.issue}`);
  
} catch (error) {
  console.error('Error:', error.message);
  process.exit(1);
}
