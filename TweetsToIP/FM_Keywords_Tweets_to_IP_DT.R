

############    Libraries      ##############
require("RPostgreSQL")
library(stringr)
library(RPostgreSQL)
library(stringdist)
library(plyr)
library(tm)
library(stringi)
library(data.table)

############    Libraries      ##############
############################################

############################################
############# FUNCTIONS   ##################
date()
#Clean the tweets before searching for keyword matching
clean_text<- function(text)
{
  text = laply(text, function(text)
  {
    # clean up sentences with R's regex-driven global substitute, gsub():
    text = gsub("[\']", " ", text)
    text = gsub('[[:punct:]]', '', text)
    text = gsub('[[:cntrl:]]', '', text)
    text = gsub('\\d+', '', text)
    text = stri_trans_general(text ,"Latin-ASCII")
    text = gsub('http\\S+\\s*', '', text)
    
    #Clean emojis
    text <- sapply(text, function(row) iconv(row, "latin1", "ASCII", sub=" "))
    names(text) <- NULL
    
    # replace al \n
    text <- gsub("[\n]", " ", text)
    
    # convert to lower case:
    text = tolower(text)
    
    return(text)
  })
  ###Remove Stopwords
  stopWords<-stopwords(kind="french")
  '%nin%' <- Negate('%in%')
  text <-lapply(text, function(x) {
    t <- unlist(strsplit(x, " "))
    t[t %nin% stopWords]
  })
  
  text <- sapply(text, paste, collapse=" ")
  
  return(text)
}

# Counts the amount of keywords presented in the tweet
count_substring = function(text,keywords) {
  subcount = function(text,keywords){
    kw = unlist(strsplit(keywords, ","))
    c=0
    for(i in length(kw)){
      if(grepl(kw[i],text)){
        c=c+1
      } else {c}
    }
    return(c/length(kw))
  }
  mapply(subcount, text, keywords, USE.NAMES = FALSE)
}
############# FUNCTIONS   ##################
############################################

# ########## ######### CONNECTION TO DB ###############
# loads the PostgreSQL driver
library(jsonlite)
login <- fromJSON("../login.json", flatten=TRUE)
drv = dbDriver("PostgreSQL")
con <- dbConnect(
  drv, dbname = login$dbname,
  host = login$host,
  port = login$port,
  user = login$user, 
  password = login$password
)
# ########## ######### CONNECTION TO DB ###############

############    KEYWORDS   #################
#query to get Interest Points
query_kw <- "
  select 
    t.id::varchar(100), t.name 
  from 
    ip.interest_points t
  where 
    t.in_use = True
  and t.id::varchar(100) not in (
      select distinct ip_id::varchar(100)
      from twitter.keywords
      )
;"

# Retreives the table from the database
names <- dbGetQuery(con, query_kw)

if(nrow(names)!=0){
    print(paste("Creating keywords for ", nrow(names), " IPs that had no keywords."))
    unwanted_array = list(    '??'='S', '??'='s', '??'='Z', '??'='z', '??'='A', '??'='A', '??'='A', '??'='A', '??'='A', '??'='A', '??'='A', '??'='C', '??'='E', '??'='E',
                              '??'='E', '??'='E', '??'='I', '??'='I', '??'='I', '??'='I', '??'='N', '??'='O', '??'='O', '??'='O', '??'='O', '??'='O', '??'='O', '??'='U',
                              '??'='U', '??'='U', '??'='U', '??'='Y', '??'='B', '??'='Ss', '??'='a', '??'='a', '??'='a', '??'='a', '??'='a', '??'='a', '??'='a', '??'='c',
                              '??'='e', '??'='e', '??'='e', '??'='e', '??'='i', '??'='i', '??'='i', '??'='i', '??'='o', '??'='n', '??'='o', '??'='o', '??'='o', '??'='o',
                              '??'='o', '??'='o', '??'='u', '??'='u', '??'='u', '??'='y', '??'='y', '??'='b', '??'='y' )
    #Remove Stopwords
    stopwordsFr<-stopwords(kind="french")
    stopwordsEn<-stopwords(kind="en")
    stopWords<- c(stopwordsEn,stopwordsFr,"lyon")
    
    names.lower<- as.data.frame(lapply(names, tolower))
    names.lower$name<- as.character(names.lower$name)
    names.lower$id <- as.character(names.lower$id)
    
    #Clean
    
    for(i in 1:nrow(names.lower)){
      #Get rid of punctuations
      names.lower[i,2]<-gsub('[[:punct:]]', " ", names.lower[i,2])
      #Get rid of symbols
      names.lower[i,2]<-gsub('[[:cntrl:]]', " ", names.lower[i,2])
      #Get rid of the accents
      names.lower[i,2]<-chartr(paste(names(unwanted_array), collapse=''),
                                 paste(unwanted_array, collapse=''),
                                 names.lower[i,2])
    }
    
    ######## Remove StopWords #####################
    '%nin%' <- Negate('%in%')
    X<-lapply(names.lower[,2], function(x) {
      t <- unlist(strsplit(x, " "))
      t[t %nin% stopWords]
    })
    
    #Remove extra spaces
    names.lower[,2]<- sapply(X, paste, collapse=",")
    keywords = names.lower[,c(1,2)]
    
    #Remove extra character
    for(i in 1:nrow(keywords)){
      keywords[i,2]<-gsub(",,,", ",", keywords[i,2])
    }
    names(keywords) = c("ip_id","keywords")
    
    ###Insert to DB

    # insert <- function(i, con, keywords) {
    #   txt <- paste("INSERT into twitter.keywords values (",keywords$ip_id[i],", '",keywords$keywords[i],"');")
    #   dbGetQuery(con, txt)
    # }
    # for (i in 1:length(keywords$ip_id)){
    #   insert(i, con, keywords)
    # }
    dbWriteTable(
        con, c("twitter","keywords"), value = keywords, append = TRUE, row.names = FALSE
    )
}
rm(query_kw)
############    KEYWORDS   #################
############################################



#####################################################
############# MODEL TWEETS_TO_IP   ##################

# Max number of tweets to process
maxTweets <- "10000"

# Queries to retrieve combinations of Tweets - Kewyords
#Keywords
query_kw <- " 
  select 
  k.ip_id, 
  k.keyword
from 
  twitter.keywords k;"

#Tweets
query_t <- "
select 
  t.idd::varchar(100), 
  t.text
from 
    twitter.tweets t
    left join twitter.processed_tweets pt on t.idd = pt.tweet_id
where pt.tweet_id is null
limit :MAX:;"

query_t <- str_replace_all(query_t, ":MAX:", maxTweets)

print(paste("Retreiving tweets from the DB. Max:", maxTweets))


# #Processed
# query_p <-"
# select distinct tweet_id::varchar(100)
# from twitter.processed_tweets"

#Get data and turn it to data table
df1 <- data.table(dbGetQuery(con, query_kw))
df <- data.table(dbGetQuery(con, query_t))
# df3 <- data.table(dbGetQuery(con, query_p))

print(paste(nrow(df), "Tweets retreived from the DB."))

setkey(df, idd)
# setkey(df3, tweet_id)
# # Subset the not processed tweets
# df <- df2[-df2[df3, which=TRUE],][1:2000]


#Prepare to update the processed tweets
processed_tweets = as.data.frame(unique(df$idd))
names(processed_tweets) = "idd"
processed_tweets$idd = as.character(processed_tweets$idd)

trigger = nrow(processed_tweets)

#Clean Text
df$text_clean = clean_text(df$text)

#Combinations for Tweets to IP
df <- merge(as.data.frame(df),as.data.frame(df1), all.x = TRUE, all.y = TRUE) 



#Count how many keywords appear in text
df$count = count_substring(df$text_clean, df$keyword)


#Only tweets to ip if there are relations
if(sum(df$count)>0){
  #tweet_to_ip = df %>% filter(count > 0) %>% select(idd, ip_id)
  tweet_to_ip = subset(df,count>0)[,c(1,4)]
  names(tweet_to_ip) = c("twitter_id","ip_id")
  tweet_to_ip<- tweet_to_ip[,c(2,1)]

  print(paste(nrow(tweet_to_ip), "relations tweet to IP found. Writing into the DB"))
  
  dbWriteTable(
      con, c("twitter","tweet_to_ip"), value = tweet_to_ip, append = TRUE, row.names = FALSE
  )
  print("Writing tweets to IP successful")
  # insert <- function(i, con, tweet_to_ip) {
  #   txt <- paste("INSERT into twitter.tweet_to_ip values (",tweet_to_ip$ip_id[i],", ",tweet_to_ip$twitter_id[i],"::bigint);")
  #   dbGetQuery(con, txt)
  # }
  # 
  # for (i in 1:length(tweet_to_ip$ip_id)){
  #   insert(i, con, tweet_to_ip)
  # }
} else {
    print("No relations tweet to ip found.")
}

#Record Processed Tweets
if(trigger[[1]]>0){ #Run if there are tweets
    print(paste("Writing", nrow(processed_tweets), "procesed tweets."))
    processed_tweets$processed_date <- Sys.time()
    dbWriteTable(
        con, c("twitter","processed_tweets"), value = processed_tweets, append = TRUE, row.names = FALSE
    )
    print("Writing processed tweets successful")
    
  # insert <- function(i, con, processed_tweets) {
  #   txt <- paste("INSERT into twitter.processed_tweets (tweet_id, processed_date) VALUES (",processed_tweets$idd[i],",  now() );")  
  #   dbGetQuery(con, txt)
  # }
  # 
  # for (i in 1:length(processed_tweets$idd)){
  #   insert(i, con, processed_tweets)
  # }
}
#########Close PostgreSQL connection###############
dbDisconnect(con)
rm(list=ls())
date()
#KeywordsTweets_to_IP
