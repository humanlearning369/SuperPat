name: Bug Report
about: Report a bug in QueryIOStatsAnalyzer (SuperPat)
title: '[BUG] '
labels: bug
assignees: ''

- Bug Description
*** Clear and concise description of what the bug is ***

- To Reproduce

- Steps to reproduce the behavior:
1. Execute stored procedure with parameters '...'
2. Observe output '...'
3. See error

-Code Sample:
-- Paste the exact code that causes the bug
EXEC dbo.QueryIOStatsAnalyzer_v2_4 
    @TableName = 'dbo.TableName',
    @LogicalReads = 12500,
    @RowCount = 1500;


- Expected Behavior
*** Clear description of what you expected to happen ***

- Actual Behavior
*** What actually happened? ***

- Environment

- SQL Server:
- Version: [e.g., SQL Server 2019]
- Edition: [e.g., Enterprise, Standard, Express]
- Build Number: [e.g., 15.0.2000.5]
- Operating System: [e.g., Windows Server 2019]

- Table Details:
  - Table Type: [Heap / Clustered Index]
  - Approximate Row Count: 
  - Approximate Size: 
  - Has LOB Columns: [Yes / No]

- QueryIOStatsAnalyzer Version:
- Version: [e.g., v2.4]
- Downloaded From: [GitHub / Other]
- Date Downloaded: 

- Error Messages
*** Paste any error messages exactly as they appear ***

***
Paste error messages here
***

- Screenshots
*** If applicable, add screenshots to help explain your problem ***



- Additional Context
*** Any other information that might help ***

- Does this happen:
  - [ ] Consistently
  - [ ] Intermittently
  - [ ] Only with specific tables
  - [ ] Only with specific parameters

- Related Issues:
*** Link to any related issues ***

- Checklist
*** Mark items you've already tried ***

- [ ] I have searched existing issues
- [ ] I am using the latest version
- [ ] I have tested on a clean environment
- [ ] I have verified my input parameters are correct
- [ ] I have checked SQL Server error logs

- Contribution
*** Would you be willing to submit a PR to fix this bug? ***

- [ ] Yes, I can submit a fix
- [ ] No, but I can help test
- [ ] No, just reporting

*** Thank you for helping improve QueryIOStatsAnalyzer (SuperPat)! ***
