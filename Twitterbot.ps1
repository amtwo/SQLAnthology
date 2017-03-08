############################################################################
#
# Params
#
############################################################################

$sqlInstance = "<SQL Instance>"
$sqlDatabase = "<database name>"
$sqlUsername = "SqlAnthology"
$sqlPassword = "<stong password>"




############################################################################
#
# from https://gallery.technet.microsoft.com/Send-Tweets-via-a-72b97964
#
############################################################################
 
workflow Send-Tweet {
    param (
    [Parameter(Mandatory=$true)][string]$Message
    )

    InlineScript {      
        [Reflection.Assembly]::LoadWithPartialName("System.Security")  
        [Reflection.Assembly]::LoadWithPartialName("System.Net")  
        
        $status = [System.Uri]::EscapeDataString($Using:Message);  
        $oauth_consumer_key = "<consumer key>";  
        $oauth_consumer_secret = "<consumer secret>";  
        $oauth_token = "<access token>";  
        $oauth_token_secret = "<access token secret>";  
        $oauth_nonce = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes([System.DateTime]::Now.Ticks.ToString()));  
        $ts = [System.DateTime]::UtcNow - [System.DateTime]::ParseExact("01/01/1970", "dd/MM/yyyy", $null).ToUniversalTime();  
        $oauth_timestamp = [System.Convert]::ToInt64($ts.TotalSeconds).ToString();  
  
        $signature = "POST&";  
        $signature += [System.Uri]::EscapeDataString("https://api.twitter.com/1.1/statuses/update.json") + "&";  
        $signature += [System.Uri]::EscapeDataString("oauth_consumer_key=" + $oauth_consumer_key + "&");  
        $signature += [System.Uri]::EscapeDataString("oauth_nonce=" + $oauth_nonce + "&");   
        $signature += [System.Uri]::EscapeDataString("oauth_signature_method=HMAC-SHA1&");  
        $signature += [System.Uri]::EscapeDataString("oauth_timestamp=" + $oauth_timestamp + "&");  
        $signature += [System.Uri]::EscapeDataString("oauth_token=" + $oauth_token + "&");  
        $signature += [System.Uri]::EscapeDataString("oauth_version=1.0&");  
        $signature += [System.Uri]::EscapeDataString("status=" + $status);  
  
        $signature_key = [System.Uri]::EscapeDataString($oauth_consumer_secret) + "&" + [System.Uri]::EscapeDataString($oauth_token_secret);  
  
        $hmacsha1 = new-object System.Security.Cryptography.HMACSHA1;  
        $hmacsha1.Key = [System.Text.Encoding]::ASCII.GetBytes($signature_key);  
        $oauth_signature = [System.Convert]::ToBase64String($hmacsha1.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($signature)));  
  
        $oauth_authorization = 'OAuth ';  
        $oauth_authorization += 'oauth_consumer_key="' + [System.Uri]::EscapeDataString($oauth_consumer_key) + '",';  
        $oauth_authorization += 'oauth_nonce="' + [System.Uri]::EscapeDataString($oauth_nonce) + '",';  
        $oauth_authorization += 'oauth_signature="' + [System.Uri]::EscapeDataString($oauth_signature) + '",';  
        $oauth_authorization += 'oauth_signature_method="HMAC-SHA1",'  
        $oauth_authorization += 'oauth_timestamp="' + [System.Uri]::EscapeDataString($oauth_timestamp) + '",'  
        $oauth_authorization += 'oauth_token="' + [System.Uri]::EscapeDataString($oauth_token) + '",';  
        $oauth_authorization += 'oauth_version="1.0"';  
    
        $post_body = [System.Text.Encoding]::ASCII.GetBytes("status=" + $status);   
        [System.Net.HttpWebRequest] $request = [System.Net.WebRequest]::Create("https://api.twitter.com/1.1/statuses/update.json");  
        $request.Method = "POST";  
        $request.Headers.Add("Authorization", $oauth_authorization);  
        $request.ContentType = "application/x-www-form-urlencoded";  
        $body = $request.GetRequestStream();  
        $body.write($post_body, 0, $post_body.length);  
        $body.flush();  
        $body.close();  
        $response = $request.GetResponse();
    }
 }


Start-Transcript -Path C:\Scripts\SQLAnthology\transcript_$(Get-Date -format yyyy_MM).txt -Append


############################################################################
#
# Step 1: Pull recent tweets into the archive
#
############################################################################
$rssList = Invoke-Sqlcmd -ServerInstance $sqlInstance -Database $sqlDatabase -Username $sqlUsername -Password $sqlPassword -Query "EXEC anthology.BlogList_Get"


$rssList | ForEach-Object {
    #Write-Host $_.blogName
    #Write-Host $_.Url

    $rss = Invoke-WebRequest $_.Url -UseBasicParsing

    if ($rss.StatusCode -ne 200){
        #This should log an error somewhere
        Write-Host "Error"
        Break
        }

    #This is the content of the RSS feed
    [xml]$rssXml = $rss.Content
    $feed = $rssXml.rss.channel
    
   
    # The blog name from the RSS feed sucks sometimes. Use what's I set up in the configuration
    $blogName = $_.blogName
    
    #Loop through all the posts
    ForEach ($msg in $Feed.Item){

        # post publish date -- We only want to tweet recent posts
        [datetime]$postPubDate = $msg.pubDate

        # author -- Exact XML element varies by blog platform
        $postAuthor = $msg.creator.InnerText
        if ($postAuthor.length -eq 0){
            $postAuthor = $msg.creator
            }


        # Title
        $postTitle = $msg.title

        # URL
        $postUrl = $msg.link
        
        $exists = $archive | Where-Object { $_.postUrl -eq $postUrl }
        
        # Add to archive if Post from the last 7 days that isn't in the archive
		if ($postPubDate -gt (Get-Date).AddDays(-7)) {
            Invoke-Sqlcmd -ServerInstance $sqlInstance -Database $sqlDatabase -Username $sqlUsername -Password $sqlPassword `
                        -Query "EXEC anthology.Archive_Upsert @PostURL = N'$($postUrl.Replace("'","''"))', @BlogName = N'$($blogName.Replace("'","''"))', @PostTitle = N'$($postTitle.Replace("'","''"))', @PostAuthor = N'$($postAuthor.Replace("'","''"))', @PostPublishDate = N'$($postPubDate)'"
        }
     }#EndForEach Tweet
    
 }#EndForEach Blog

############################################################################
#
# Step 2: Post a single untweeted tweet from the archive 
#
############################################################################

# Pick one random untweeted post to be tweeted
$untweeted = Invoke-Sqlcmd -ServerInstance $sqlInstance -Database $sqlDatabase -Username $sqlUsername -Password $sqlPassword -Query "EXEC anthology.Archive_GetNextTweet"
$untweeted.TweetText

if(($untweeted.TweetText).length -gt 1){
    try{
        # Send the tweet
        $null = Send-Tweet $untweeted.TweetText

        # Mark this post as tweeted
        Invoke-Sqlcmd -ServerInstance $sqlInstance -Database $sqlDatabase -Username $sqlUsername -Password $sqlPassword -Query "EXEC anthology.Archive_Upsert @PostURL = N'$($untweeted.postUrl.Replace("'","''"))',@TweetText = N'$($untweeted.TweetText.Replace("'","''"))', @IsTweeted = 1"
        }
    catch{
        Write-Host "Error tweeting"
        #yea, I should do actual error logging, eh?
        }
}

############################################################################
############################################################################


Stop-Transcript
