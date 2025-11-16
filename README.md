# This script is part of SuperPat coming soon!

QueryIOStatsAnalyzer_v2_4
A field-ready T-SQL procedure that gives you a user-friendly/readable output on STATISTICS IO. Think in pages...
/*
***************************************************************************
QueryIOStatsAnalyzer v2.4 is part of SUPER PAT (Performance Analysis Tool) - THIS SCRIPT AND SUPERPAT ARE A WORK IN PROGRESS...
***************************************************************************

Copyright (C) 2025 Aegis-IO

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

IMPORTANT NOTICE - AGPL-3.0 REQUIREMENTS:

- If you run this on a network server, you MUST make source code available
- 
- Any modifications MUST be released under AGPL-3.0
- 
- You MUST preserve this copyright notice
- 
- Network use = distribution (triggers copyleft obligations)
- 

Project Repository: https://github.com/humanlearning369/SuperPat

Issue Tracker: https://github.com/humanlearning369/SuperPat/issues

***************************************************************************
*/
***************************************************************************
OVERVIEW – DEVELOPMENT BUILD. TEST BEFORE PRODUCTION USE.

This stored procedure analyzes logical and physical reads for a specific table and returns a diagnostic breakdown of efficiency, data access patterns, and potential issues. It bridges what STATISTICS IO shows and what your query actually did.

Pass in table name, logical reads, and row count. Optionally include LOB reads, CPU time, and tempdb deltas for spill detection. Get back a one-screen summary with clarity, context, and confidence.
***************************************************************************
HOW TO:

SET STATISTICS IO ON

SELECT * FROM dbo.Orders WHERE OrderDate > '2024-01-01'

/*
Table 'Orders'. Scan count 1, logical reads 12500
*/

EXEC dbo.QueryIOStatsAnalyzer_v2_4

@TableName = 'dbo.Orders',

@LogicalReads = 12500,

@RowCount = 1500
***************************************************************************
WHAT’S THE DEAL WITH THE OUTPUT COLUMNS

DatabaseName - Current database name

TableName - Analyzed table (schema-qualified)

BaseStructure - 'Heap' or 'Clustered Index'

ScanCount - Scan count from STATISTICS IO (if provided)

LogicalReads - In-row pages read from cache

LobLogicalReads - LOB pages read from cache (if provided)

TotalLogicalReads - LogicalReads + LobLogicalReads (when @IncludeLob=1)

PhysicalReads - Pages read from disk (optional input)

RowsReturned - Rows returned by query

AvgRowBytes - Average row size in bytes

AvgPageSpaceUsedPct - Average % of page space utilized

RowsPerLeafPage - Estimated rows per data page

TableLeafPages - Total leaf pages in base structure

ForwardedRecords - Count of forwarded records (heaps only)

DataReadMB - Megabytes of data read (total)

PercentOfTableTouched - % of table scanned (capped at 100%)

EstElapsedMs - Estimated elapsed time in milliseconds

PagesPerRow - I/O cost per row (lower is better)

EfficiencyGrade - EXCELLENT / GOOD / FAIR / POOR

AccessPatternHint - Likely Seek / Index Scan / Table Scan

Confidence - HIGH / MED / LOW reliability of analysis

SpillDetected - 1 if tempdb spill detected, 0 otherwise

StorageAssumed - SSD or HDD (affects timing estimates)

ScanModeUsed - SAMPLED or DETAILED

LobIncluded - Whether LOB data was included

Hint - Actionable suggestion for optimization

ResultSummary - Natural language summary of findings

***************************************************************************

COMMON MISTAKES TO AVOID:

Passing non-schema-qualified table names (will fail)

Use: 'dbo.Orders' not 'Orders'

Setting @IncludeLob=1 without passing @LobLogicalReads

Check STATISTICS IO for "lob logical reads" and include it

Forgetting to enable STATISTICS IO before running queries

Always SET STATISTICS IO ON first

Analyzing multiple tables' reads with single call

One call per table; for joins, analyze each table separately

Using on tiny sample queries for production tuning

Use representative data volumes for accurate assessment

***************************************************************************

WHAT MAKES THIS PROCEDURE COOL:

Accurate calculations using empirical page fill (8096 × usage%)

Handles all edge cases (empty tables, LOB data, nulls, tiny tables)

Precise spill detection with optional before/after deltas

Adaptive logic for different table sizes (<100 pages)

Clear, actionable output with confidence scoring

Flexible performance (sampled vs detailed modes)

Developer-friendly hints for immediate action

Comprehensive documentation and real-world examples

Proper LOB accounting (numerator/denominator alignment)

Warning hints for common misconfigurations

***************************************************************************

TROUBLESHOOTING

Q: I'm getting NULL for PercentOfTableTouched

A: Table might be empty, or statistics are out of date. Run UPDATE STATISTICS.

Q: My % touched shows as 100% but I know it's a seek

A: For tiny tables, even a seek can touch significant %. Check TableLeafPages.

Q: Confidence is LOW even though results look clear

A: Low row count with high reads. Indicates potential missing index or bad stats.

Q: Warning about @LobLogicalReads

A: You set @IncludeLob=1 but didn't provide LOB reads. Check STATISTICS IO output.

Q: Empty or New Table message

A: Table has no data pages. Insert data or check if table was just created or truncated.

***************************************************************************

NOTES:

•	Requires SQL Server 2012+ (FORMAT function)

•	Requires VIEW DATABASE STATE permission

•	No dependencies or temp objects created

•	Works in tempdb for temp tables

•	Use one call per table for accuracy

***************************************************************************

SUMMARY

STATISTICS IO tells you what SQL Server did.

This procedure tells you what it means.

When your query burns 100K pages to return 50 rows, this will call it out.

