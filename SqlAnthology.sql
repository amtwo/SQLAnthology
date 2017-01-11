CREATE USER SQLAnthology WITH PASSWORD = '<strong password>';
GO
CREATE SCHEMA anthology AUTHORIZATION SQLAnthology;
GO

--DROP TABLE anthology.Blog
CREATE TABLE anthology.Blog(
	BlogID       int identity(1,1),
	DisplayName   nvarchar(30) COLLATE Latin1_General_CI_AS,
	RssUri nvarchar(200) COLLATE Latin1_General_CI_AS,
	CONSTRAINT PK_anthologyBlog PRIMARY KEY CLUSTERED (BlogID)
	);
GO
SET IDENTITY_INSERT anthology.Blog ON
INSERT INTO anthology.Blog (BlogID, DisplayName,RssUri)
VALUES (1,N'Andy Mallon', N'https://www.am2.co/feed/'),
       (2,N'SentryOne', N'https://blogs.sentryone.com/feed/'),
	   (3,N'Ken Fisher', N'https://sqlstudies.com/feed/'),
	   (4,N'dbatools',N'https://dbatools.io/category/announcements/feed/'),
	   (5,N'dbareports',N'https://dbareports.io/category/announcements/feed/'),
	   (6,N'Mike Kane',N'http://www.michaelkane.me/feed/'),
	   (7,N'SQLPerformance',N'https://sqlperformance.com/feed/'),
	   (8,N'Brent Ozar Unlimited',N'https://www.brentozar.com/blog/feed/'),
	   (9,N'Brent Ozar',N'https://ozar.me/feed/');
SET IDENTITY_INSERT anthology.Blog OFF
GO

--DROP TABLE anthology.BlogAuthor
CREATE TABLE anthology.BlogAuthor(
	BlogID      int,
	AuthorName    nvarchar(50) COLLATE Latin1_General_CI_AS,
	TwitterHandle nvarchar(30) COLLATE Latin1_General_CI_AS,
	CONSTRAINT PK_anthologyBlogAuthor PRIMARY KEY CLUSTERED (BlogID,AuthorName)
	);
GO
INSERT INTO anthology.BlogAuthor (BlogID, AuthorName,TwitterHandle)
VALUES (1,N'Andy', N'@AMtwo 🏳️‍🌈');
GO


CREATE OR ALTER PROCEDURE anthology.BlogList_Get
AS
SET NOCOUNT ON
SELECT BlogName = DisplayName,
       [Url]    = RssUri
FROM anthology.Blog;
GO

--DROP TABLE anthology.Archive
CREATE TABLE anthology.Archive (
	PostUrl nvarchar(200) COLLATE Latin1_General_CI_AS,
	BlogName nvarchar(30) COLLATE Latin1_General_CI_AS,
	PostTitle  nvarchar(150) COLLATE Latin1_General_CI_AS,
	PostAuthor nvarchar(50) COLLATE Latin1_General_CI_AS,
	PostPublishDate datetime2(0),
	TweetText nvarchar(340) COLLATE Latin1_General_CI_AS, --Make sure we support emoji
	IsTweeted bit NOT NULL CONSTRAINT DF_anthologyIsTweeted DEFAULT 0,
	CONSTRAINT PK_anthologyArchive PRIMARY KEY CLUSTERED (PostUrl) WITH (DATA_COMPRESSION=PAGE),
	);
GO
--TweetText is 340 because I'm not storing the shortened URL. Twitter doesn't count the full URL length.
CREATE INDEX IX_anthologyArchiveUntweeted 
	ON anthology.Archive (BlogName, PostTitle, PostAuthor, PostUrl)
	WHERE IsTweeted = 0;
GO



CREATE OR ALTER PROCEDURE anthology.Archive_GetNextTweet
AS
SET NOCOUNT ON
DECLARE @TweetText nvarchar(340),
        @PostURL nvarchar(200)
SELECT TOP 1 @TweetText = N'[' + BlogName + N']' + N' ✒️ ' + COALESCE(ba.TwitterHandle,a.PostAuthor) 
						+ NCHAR(10) + NCHAR(13) + PostTitle,
			 @PostURL = PostUrl
FROM anthology.Archive a
LEFT JOIN anthology.Blog b ON b.DisplayName = a.BlogName
LEFT JOIN anthology.BlogAuthor ba ON ba.BlogID = b.BlogID AND ba.AuthorName = a.PostAuthor
WHERE IsTweeted = 0
ORDER BY NEWID();

IF LEN(@TweetText) > 119
BEGIN
	SET @TweetText = SUBSTRING(@TweetText,1,115) + N'…' + CHAR(10) + @PostURL
END;
ELSE
BEGIN
	SET @TweetText = @TweetText + CHAR(10) + @PostURL
END;

SELECT PostURL= @PostURL,
       TweetText = @TweetText
GO

CREATE OR ALTER PROCEDURE anthology.Archive_Upsert
	@PostUrl nvarchar(200),
	@BlogName varchar(30) = NULL,
	@PostTitle nvarchar(150) = NULL,
	@PostAuthor varchar(50) = NULL,
	@PostPublishDate datetime2(0) = NULL,
	@TweetText nvarchar(340) = NULL,
	@IsTweeted bit = NULL
AS
SET NOCOUNT ON
UPDATE a
   SET BlogName        = COALESCE(@BlogName,BlogName),
	   PostTitle       = COALESCE(@PostTitle,PostTitle),
	   PostAuthor      = COALESCE(@PostAuthor,PostAuthor),
	   PostPublishDate = COALESCE(@PostPublishDate,PostPublishDate),
	   TweetText       = COALESCE(@TweetText,TweetText),
	   IsTweeted       = COALESCE(@IsTweeted,IsTweeted)
  FROM anthology.Archive a
 WHERE PostUrl = @PostUrl;

IF @@ROWCOUNT = 0
BEGIN
	INSERT INTO anthology.Archive (PostURL, BlogName, PostTitle,PostAuthor, PostPublishDate, TweetText, IsTweeted)
	SELECT @PostURL, @BlogName, @PostTitle, @PostAuthor, @PostPublishDate, @TweetText, COALESCE(@IsTweeted,0);
END;
GO
