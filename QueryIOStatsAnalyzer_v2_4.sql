USE [YOUR DATABASE NAME HERE]
GO

/****** Object:  StoredProcedure [dbo].[QueryIOStatsAnalyzer_v2_4]    Script Date: 11/16/2025 5:53:43 PM 
IMPORTANT NOTE: This procedure is still being tested. Please do your own research as well.
***************************************************************************
Copyright (C) 2025 Aegis-IO
***************************************************************************

This software is licensed under the GNU Affero General Public License v3.0 
(AGPL-3.0).

***************************************************************************
IMPORTANT LEGAL NOTICES
***************************************************************************

AGPL-3.0 LICENSE REQUIREMENTS:

This license is STRICTER than GPL because it applies to network use.

IF YOU USE THIS SOFTWARE ON A NETWORK SERVER, YOU MUST:

1. Make the complete source code (including modifications) available to users
2. Provide a prominent notice about how to obtain the source
3. License all modifications under AGPL-3.0
4. Preserve all copyright, patent, trademark, and attribution notices

***************************************************************************
CONTACT INFORMATION
***************************************************************************

For license questions, compliance issues, or other inquiries:

Email: team-aegisio@outlook.com
GitHub: @humanlearning369
Repository: https://github.com/humanlearning369/SuperPat

***************************************************************************/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.QueryIOStatsAnalyzer_v2_4','P') IS NOT NULL
    DROP PROCEDURE dbo.QueryIOStatsAnalyzer_v2_4;
GO
	
CREATE PROCEDURE [dbo].[QueryIOStatsAnalyzer_v2_4]
    @TableName SYSNAME,                      -- must include schema to qualify (i.e.,  dbo.Table1)
    @LogicalReads BIGINT,                    -- get this from STATISTICS IO output -> 'logical reads'
    @RowCount BIGINT,
    @PhysicalReads BIGINT = NULL,
    @ScanCount INT = NULL,                   -- get this from STATISTICS IO output -> 'Scan count'
    @LobLogicalReads BIGINT = NULL,          -- get this from STATISTICS IO output -> 'lob logical reads'
    @CpuTimeMs INT = NULL,                   -- CPU time or elapsed time in ms
    @StorageType VARCHAR(10) = 'SSD',
    @ScanMode VARCHAR(10) = 'SAMPLED',       -- 'SAMPLED' or 'DETAILED' - one is fast and the other is slower
    @IncludeLob BIT = 0,                     -- I want LOB_DATA and ROW_OVERFLOW_DATA in calculations
    @TempdbUserAllocDelta INT = NULL,        -- WARNING! This is optional and work in progress - user object page delta for precise spill detection
    @TempdbInternalAllocDelta INT = NULL     -- WARNING! This is optional and work in progress - internal object page delta for precise spill detection
AS
BEGIN
    SET NOCOUNT ON

    DECLARE 
        @ObjId INT = OBJECT_ID(@TableName),
        @LeafPages BIGINT,
        @AvgRowBytes DECIMAL(10,2),
        @AvgPageSpaceUsedPct DECIMAL(5,2),
        @RowsPerLeafPage DECIMAL(10,2),
        @PctOfTable DECIMAL(10,2),
        @EstDataMB DECIMAL(10,2),
        @CostPerRow DECIMAL(10,3),
        @EstElapsedMs DECIMAL(10,2),
        @IOmsPerPage DECIMAL(10,3),
        @Grade VARCHAR(12),
        @AccessPattern VARCHAR(30),
        @ConfidenceScore VARCHAR(10),
        @SpillDetected BIT = 0,
        @BaseStructure VARCHAR(20),
        @ForwardedRecords BIGINT,
        @Hint NVARCHAR(MAX),
        @ResultSummary NVARCHAR(500),
        @TotalLogicalReads BIGINT
   
    IF @ObjId IS NULL
    BEGIN        
        IF @TableName LIKE '%#%'
        BEGIN            
            SELECT @ObjId = object_id 
            FROM tempdb.sys.objects 
            WHERE name LIKE REPLACE(SUBSTRING(@TableName, CHARINDEX('#', @TableName), LEN(@TableName)), 'tempdb.dbo.', '') + '%'
              AND type IN ('U', 'TT')
            
            IF @ObjId IS NULL
            BEGIN
                RAISERROR('Temp table not found. Ensure it exists in current session.',16,1)
                RETURN
            END
        END
        ELSE
        BEGIN
            RAISERROR('Table not found. Use schema-qualified name (e.g., dbo.Table1).',16,1)
            RETURN
        END
    END

    IF @ScanMode NOT IN ('SAMPLED', 'DETAILED')
    BEGIN
        RAISERROR('Invalid @ScanMode. Use ''SAMPLED'' or ''DETAILED''.',16,1)
        RETURN
    END

    SET @TotalLogicalReads = @LogicalReads + 
                             CASE WHEN @IncludeLob = 1 THEN ISNULL(@LobLogicalReads, 0) ELSE 0 END

    DECLARE @DbId INT = CASE WHEN @TableName LIKE '%#%' THEN DB_ID('tempdb') ELSE DB_ID() END
    
    ;WITH phys AS (
        SELECT 
            index_id,
            SUM(CASE WHEN index_level = 0 THEN page_count ELSE 0 END) AS LeafPages,
            MAX(CASE WHEN index_level = 0 THEN avg_record_size_in_bytes END) AS AvgRowBytes,
            MAX(CASE WHEN index_level = 0 THEN avg_page_space_used_in_percent END) AS AvgPageSpaceUsedPct,
            MAX(CASE WHEN index_level = 0 AND index_id = 0 THEN forwarded_record_count END) AS ForwardedRecords
        FROM sys.dm_db_index_physical_stats(@DbId, @ObjId, NULL, NULL, @ScanMode)
        WHERE alloc_unit_type_desc IN (
                'IN_ROW_DATA',
                CASE WHEN @IncludeLob = 1 THEN 'LOB_DATA' END,
                CASE WHEN @IncludeLob = 1 THEN 'ROW_OVERFLOW_DATA' END
              )
          AND index_id IN (0, 1)  -- 0 = Heap, 1 = Clustered Index
          AND index_level = 0     -- = Leaf level
        GROUP BY index_id
    )
    SELECT 
        @LeafPages = LeafPages,
        @AvgRowBytes = AvgRowBytes,
        @AvgPageSpaceUsedPct = AvgPageSpaceUsedPct,
        @ForwardedRecords = ForwardedRecords,
        @BaseStructure = CASE index_id 
                            WHEN 0 THEN 'Heap' 
                            WHEN 1 THEN 'Clustered Index' 
                            ELSE 'Unknown' 
                         END
    FROM phys

    IF @LeafPages IS NULL OR @LeafPages = 0
    BEGIN
        SET @AccessPattern = 'Empty or New Table'
        SET @ConfidenceScore = 'N/A'
        SET @Grade = 'N/A'
        SET @PctOfTable = NULL
        SET @CostPerRow = NULL
        SET @RowsPerLeafPage = NULL
        SET @EstElapsedMs = 0
        SET @ResultSummary = 'Table has no data pages. Cannot compute I/O statistics.'
        
        SELECT
            DB_NAME()                         AS DatabaseName,
            @TableName                        AS TableName,
            ISNULL(@BaseStructure, 'Unknown') AS BaseStructure,
            @ScanCount                        AS ScanCount,
            @LogicalReads                     AS LogicalReads,
            @LobLogicalReads                  AS LobLogicalReads,
            @TotalLogicalReads                AS TotalLogicalReads,
            @PhysicalReads                    AS PhysicalReads,
            @RowCount                         AS RowsReturned,
            NULL                              AS AvgRowBytes,
            NULL                              AS AvgPageSpaceUsedPct,
            NULL                              AS RowsPerLeafPage,
            CAST(0 AS BIGINT)                 AS TableLeafPages,
            NULL                              AS ForwardedRecords,
            NULL                              AS DataReadMB,
            NULL                              AS PercentOfTableTouched,
            CAST(0 AS DECIMAL(10,2))          AS EstElapsedMs,
            NULL                              AS PagesPerRow,
            @Grade                            AS EfficiencyGrade,
            @AccessPattern                    AS AccessPatternHint,
            @ConfidenceScore                  AS Confidence,
            CAST(0 AS BIT)                    AS SpillDetected,
            @StorageType                      AS StorageAssumed,
            @ScanMode                         AS ScanModeUsed,
            @IncludeLob                       AS LobIncluded,
            N'N/A - Table is empty'           AS Hint,
            @ResultSummary                    AS ResultSummary
        RETURN
    END

    DECLARE @UsableBytes DECIMAL(10,2) = 8096.0 * (ISNULL(@AvgPageSpaceUsedPct, 100.0) / 100.0)
    SET @RowsPerLeafPage = CASE WHEN @AvgRowBytes > 0 THEN @UsableBytes / @AvgRowBytes ELSE NULL END

    SET @EstDataMB = (@TotalLogicalReads * 8.0) / 1024.0    

    SET @PctOfTable = CASE WHEN @LeafPages > 0 
                          THEN CAST(
                                  CASE WHEN (@TotalLogicalReads * 1.0 / @LeafPages) * 100.0 > 100.0 
                                       THEN 100.0 
                                       ELSE (@TotalLogicalReads * 1.0 / @LeafPages) * 100.0 
                                  END AS DECIMAL(10,2))
                          ELSE NULL 
                      END
    
    SET @CostPerRow = CASE WHEN @RowCount > 0 THEN @TotalLogicalReads * 1.0 / @RowCount ELSE NULL END

    SET @IOmsPerPage = CASE UPPER(@StorageType)
                           WHEN 'HDD' THEN 0.8
                           ELSE 0.10
                       END
    SET @EstElapsedMs = @TotalLogicalReads * @IOmsPerPage    
   
    IF @CpuTimeMs IS NOT NULL SET @EstElapsedMs = @CpuTimeMs

    SET @Grade = CASE 
                    WHEN @CostPerRow < 0.1 THEN 'Excellent'
                    WHEN @CostPerRow < 1 THEN 'Good'
                    WHEN @CostPerRow < 5 THEN 'Ok'
                    ELSE 'Poor'
                 END

    IF (@TempdbUserAllocDelta IS NOT NULL AND @TempdbUserAllocDelta > 0) OR
       (@TempdbInternalAllocDelta IS NOT NULL AND @TempdbInternalAllocDelta > 0)
        SET @SpillDetected = 1
    ELSE IF EXISTS (
        SELECT 1 
        FROM sys.dm_db_task_space_usage 
        WHERE session_id = @@SPID 
          AND (user_objects_alloc_page_count > 0 OR internal_objects_alloc_page_count > 0)
    )
        SET @SpillDetected = 1

    SET @AccessPattern = CASE 
                            WHEN @PctOfTable >= 80 THEN 'Table scan likely'
                            WHEN @PctOfTable >= 10 THEN 'Index scan likely'
                            ELSE 'Seek'
                         END

    IF (@LeafPages IS NOT NULL AND @LeafPages < 100)
    BEGIN        
        IF     @PctOfTable >= 60 SET @AccessPattern = 'Table scan likely'
        ELSE IF @PctOfTable >= 6  SET @AccessPattern = 'Index scan likely'
        ELSE                      SET @AccessPattern = 'Seek'
    END

    SET @ConfidenceScore = CASE                                
                               WHEN @LeafPages IS NULL OR @TotalLogicalReads IS NULL THEN 'LOW'
                               WHEN @PctOfTable IS NULL THEN 'LOW'                               
                               
                               WHEN @RowCount < 10 AND @TotalLogicalReads > 1000 THEN 'LOW'
                               WHEN @RowCount < 100 AND @TotalLogicalReads > 10000 THEN 'LOW'                               
                               
                               WHEN @PctOfTable >= 90 OR @PctOfTable <= 5 THEN 'HIGH'                               
                               
                               WHEN @PctOfTable BETWEEN 5 AND 90 THEN 'MED'
                               
                               ELSE 'LOW'
                           END

    IF @SpillDetected = 1 AND @ConfidenceScore = 'HIGH' SET @ConfidenceScore = 'MED'
    IF @CostPerRow > 10 SET @ConfidenceScore = 'MED'

    ----------------------------------------------------------------------
    -- hints
	----------------------------------------------------------------------

    DECLARE @Hints TABLE (HintOrder INT, HintText NVARCHAR(500))
	DECLARE @HintCount INT = 0

	IF @IncludeLob = 1 AND @LobLogicalReads IS NULL
	BEGIN
		SET @HintCount += 1
		INSERT INTO @Hints VALUES
			(@HintCount, N'@IncludeLob = 1 but LOB reads not provided; % of table touched may be off. NOTE: Please do your own research as well.')
	END

	IF @ForwardedRecords IS NOT NULL AND @ForwardedRecords > 0
	BEGIN
		SET @HintCount += 1
		INSERT INTO @Hints VALUES
			(@HintCount, N'Heap has forwarded records; consider a clustered index or rebuild. NOTE: Please do your own research as well')
	END
	
	--IF @ConfidenceScore = 'LOW'
	--AND @RowCount <= 10
	--AND @TotalLogicalReads > 1000
	IF @RowCount <= 10 AND @TotalLogicalReads > 1000
	BEGIN
		SET @HintCount += 1
		INSERT INTO @Hints VALUES
			(@HintCount, N'Low-selectivity or non-sargable predicate suspected; check filters and indexing. NOTE: Please do your own research as well')
	END

	IF @AccessPattern LIKE '%scan likely%'
		AND @CostPerRow IS NOT NULL
		AND @CostPerRow > 5
		AND @PctOfTable IS NOT NULL
		AND @PctOfTable >= 50
	BEGIN
		SET @HintCount += 1
		INSERT INTO @Hints VALUES
			(@HintCount, N'I/O-heavy scan; consider indexing filter column(s) or making the predicate more selective. NOTE: Please do your own research as well')
	END

	IF (
			@AccessPattern LIKE '%scan likely%'
			OR @AccessPattern = 'Seek'
		)
	AND @CostPerRow IS NOT NULL
	AND @CostPerRow > 10
	AND (@PctOfTable IS NULL OR @PctOfTable < 50)
	AND NOT (@RowCount <= 10 AND @TotalLogicalReads > 1000)
	BEGIN
		SET @HintCount += 1
		INSERT INTO @Hints VALUES
			(@HintCount, N'High pages-per-row; likely key lookups or wide scans. Consider a covering index with INCLUDE columns or trimming the SELECT list. NOTE: Please do your own research as well')
	END

	IF @SpillDetected = 1
	BEGIN
		SET @HintCount += 1
		INSERT INTO @Hints VALUES
			(@HintCount, N'Tempdb spill detected; review memory grant, row goals, stats, or add an ORDER BY/index to avoid sort/hash spills. NOTE: Please do your own research as well')
	END

	IF @HintCount = 0
	BEGIN
		SET @Hint = N''
	END	
	ELSE IF @HintCount = 1
	BEGIN
		SELECT @Hint = HintText
		FROM @Hints
		WHERE HintOrder = 1
	END
	ELSE
	BEGIN    
		SET @Hint = N''

		SELECT @Hint = COALESCE(@Hint + CHAR(13) + CHAR(10), N'')
					+ CAST(HintOrder AS NVARCHAR(2)) + N'. ' + HintText
		FROM @Hints
		ORDER BY HintOrder
	END

    ----------------------------------------------------------------------
    -- res
	----------------------------------------------------------------------

    SET @ResultSummary = CONCAT(
        'Query touched approximately ', 
        FORMAT(@PctOfTable, 'N1'), '% of ', @BaseStructure, ' (',
        CASE WHEN @IncludeLob = 1 AND @LobLogicalReads > 0
             THEN CONCAT(FORMAT(@LogicalReads, 'N0'), ' in-row + ', 
                        FORMAT(@LobLogicalReads, 'N0'), ' LOB = ',
                        FORMAT(@TotalLogicalReads, 'N0'), ' total pages')
             ELSE CONCAT(FORMAT(@TotalLogicalReads, 'N0'), ' pages')
        END,
        ' ≈ ', FORMAT(@EstDataMB, 'N1'), ' MB',
        CASE WHEN @CpuTimeMs IS NOT NULL 
             THEN ', elapsed override used'
             ELSE ''
        END,
        ') ',
        'returning ', FORMAT(@RowCount, 'N0'), ' rows. ',
        CASE 
            WHEN @AccessPattern LIKE '%Seek%' THEN 'Behavior consistent with a selective seek pattern. '
            WHEN @AccessPattern LIKE '%scan likely%' THEN 'Behavior consistent with a medium-range scan. '
            ELSE 'Behavior consistent with a full table scan. '
        END,
        'I/O efficiency rated ', @Grade, 
        ' (', FORMAT(@CostPerRow, 'N2'), ' pages/row) ',
        'with confidence ', @ConfidenceScore, '. ',
        CASE WHEN @SpillDetected = 1 
             THEN 'Tempdb usage detected. '
             ELSE ''
        END,
        CASE WHEN @ScanMode = 'SAMPLED' 
             THEN 'Stats based on sampled data.'
             ELSE 'Stats based on detailed scan.'
        END
    )

    ----------------------------------------------------------------------
    -- it's done.
    ----------------------------------------------------------------------
    SELECT
        DB_NAME()                         AS DatabaseName,
        @TableName                        AS TableName,
        @BaseStructure                    AS BaseStructure,
        @ScanCount                        AS ScanCount,
        @LogicalReads                     AS LogicalReads,
        @LobLogicalReads                  AS LobLogicalReads,
        @TotalLogicalReads                AS TotalLogicalReads,
        @PhysicalReads                    AS PhysicalReads,
        @RowCount                         AS RowsReturned,
        @AvgRowBytes                      AS AvgRowBytes,
        @AvgPageSpaceUsedPct              AS AvgPageSpaceUsedPct,
        @RowsPerLeafPage                  AS RowsPerLeafPage,
        @LeafPages                        AS TableLeafPages,
        @ForwardedRecords                 AS ForwardedRecords,
        @EstDataMB                        AS DataReadMB,
        @PctOfTable                       AS PercentOfTableTouched,
        @EstElapsedMs                     AS EstElapsedMs,
        @CostPerRow                       AS PagesPerRow,
        @Grade                            AS EfficiencyGrade,
        @AccessPattern                    AS AccessPatternHint,
        @ConfidenceScore                  AS Confidence,
        @SpillDetected                    AS SpillDetected,
        @StorageType                      AS StorageAssumed,
        @ScanMode                         AS ScanModeUsed,
        @IncludeLob                       AS LobIncluded,
        @Hint                             AS Hint,
        @ResultSummary                    AS ResultSummary
    
END
