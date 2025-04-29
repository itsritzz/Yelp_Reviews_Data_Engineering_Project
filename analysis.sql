-- Pulling data from s3 and creating yelp_reviews table
create or replace table yelp_reviews (review_text variant)

COPY INTO yelp_reviews
FROM 's3://learnsqlritz121/yelp/'
CREDENTIALS = (
    AWS_KEY_ID = '******'
    AWS_SECRET_KEY = '******'
)
FILE_FORMAT = (TYPE = JSON);

-- checking data
select * from yelp_reviews limit 10

-- creating custom function to check sentiment analysis
CREATE OR REPLACE FUNCTION analyze_sentiment(text STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('vaderSentiment')
HANDLER = 'sentiment_analyzer'
AS $$
from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

def sentiment_analyzer(text):
    if not hasattr(sentiment_analyzer, "analyzer"):
        sentiment_analyzer.analyzer = SentimentIntensityAnalyzer()  # create once and reuse
    scores = sentiment_analyzer.analyzer.polarity_scores(text)
    if scores['compound'] >= 0.05:
        return 'Positive'
    elif scores['compound'] <= -0.05:
        return 'Negative'
    else:
        return 'Neutral'
$$;


-- creating final tbl_yelp_reviews table
create or replace table tbl_yelp_reviews as
select review_text:business_id::string as business_id,
review_text:user_id::string as review_user_id,
review_text:date::date as review_date,
review_text:stars::number as review_stars,
review_text:text::string as review_text,
analyze_sentiment(review_text) as review_sentiment
from yelp_reviews

-- checking data
select * from tbl_yelp_reviews limit 10

-- creating yelp_businesses table
create or replace table yelp_businesses (business_text variant)

COPY INTO yelp_businesses
FROM 's3://learnsqlritz121/yelp/yelp_academic_dataset_business.json'
CREDENTIALS = (
    AWS_KEY_ID = '******'
    AWS_SECRET_KEY = '************'
)
FILE_FORMAT = (TYPE = JSON);

select * from yelp_businesses limit 10

-- creating tbl_yelp_businesses table
create or replace table tbl_yelp_businesses as
select business_text:business_id::string as business_id,
business_text:name::string as business_name,
business_text:city::string as business_city,
business_text:state::string as business_state,
business_text:stars::number as business_stars,
business_text:review_count::number as business_review_count,
business_text:categories::string as business_categories
from yelp_businesses

-- checking the data
select * from tbl_yelp_businesses limit 10

-- SQL ANALYTICS --
-- 1. What are the number of businesses in each category

with cte as
(select business_id, trim(cat.value) as business_cat
from tbl_yelp_businesses,
lateral split_to_table(business_categories,',') cat
)
select business_cat, count(*) no_of_business
from cte
group by business_cat
order by no_of_business desc
limit 10

--2. Find the top 10 users who have reviewed the most businesses in the 'restaurant' category.

select r.review_user_id,COUNT(distinct r.business_id) no_of_businesses
from tbl_yelp_reviews r
inner join tbl_yelp_businesses b
ON r.business_id = b.business_id
where b.business_categories ilike '%restaurant%'
group by r.review_user_id
order by no_of_businesses desc
limit 10