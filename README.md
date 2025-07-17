# CSharp-DevOps-Suite

#### WORKING well enough you could use it, needs issues hammered out, no time right now

#### sln/csproj/cs files are just to make it easy to edit and manage git operations within the same IDE window

- This is a comprehensive test suite which performs many operations and generates reports of it's findings
- The special tool "Generate-Comprehensive-Report.ps1 will give a high level overview of project health
- There is also another special tool, Generate-Corruption-Report.ps1 run it and see how it looks :)
- You can then drill down to get more detail and resolve issues found within the reports.
- Reports can be automated via task I believe
- Nice menu for easy interaction, audit, and report generation

## How does it work?
Well I don't have the time to explain in detail. Simple version is to clone this repository, 
and copy the contents into your C# project root directory like so:
- My_Super_Awesome_Project/
  - My_Super_Awesome_Project.sln
  - My_Super_Awesome_Project.csproj
  - Scripts/
  - DevOps-ScriptLauncher.bat
 
Installation is that simple. Now run the batch script - which is important as it sets the execution
policy enabling powershell script usage (required)

Figure the menu out on your own, it is self explanatory. Suggest features on issue ticket page.

# END OF NON-COMPREHENSIVE DOCUMENTATION

YES COPILOT GENERATED THE BORING SCRIPTS FOR ME AND I INSTRUCTED AND CONSTRAINED IT.
GET OFF MY BACK I DONT KNOW POWERSHELL LOOK AT THIS BEAUTIFUL WORK!

Copilot / Anthropic Claude Sonnet 4 model is a great developer and teacher :)

### Readme & release is coming eventually :P
