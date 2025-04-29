# Yelp Reviews Data Analytics Project

## Project Overview
This end-to-end data analytics project analyzes Yelp business reviews data to gain insights into customer sentiment and business performance. The project processes approximately 7 million review records from Yelp's publicly available dataset, performing both sentiment analysis and general data analysis.

![Project Architecture](https://github.com/itsritzz/Yelp_Reviews_Data_Engineering_Project/blob/main/resource/Flow_diagram.png)

## Dataset
The project uses Yelp's academic dataset which consists of:
- **Reviews Data**: ~7 million records (5GB JSON file)
- **Business Data**: ~150K records (100MB JSON file)

The dataset contains information about businesses, including location, categories, ratings, and customer reviews.

## Tech Stack
- **Python**: For data preprocessing and file splitting
- **AWS S3**: For data storage and retrieval
- **Snowflake**: For data warehousing and SQL analysis
- **User-Defined Functions (UDF)**: Python UDF for sentiment analysis using VaderSentiment
- **SQL**: For data analysis and insights generation

## Project Workflow

### 1. Data Preprocessing
- Downloaded JSON data from Yelp's academic dataset
- Developed a Python script to split the large 5GB reviews file into smaller chunks (recommended 20-25 files)
- This splitting enables parallel processing during data ingestion

```python
# Python code to split large JSON file into smaller chunks
# Code splits the file based on number of lines and desired number of output files
# Each output file maintains proper JSON format
```

### 2. Data Storage
- Created an AWS S3 bucket
- Uploaded the split review files and business data to S3
- Set up proper access credentials for Snowflake to access the S3 bucket

### 3. Data Ingestion into Snowflake
- Created Snowflake tables with VARIANT data type to store the JSON data
```sql
-- Creating initial tables for JSON data
CREATE OR REPLACE TABLE yelp_reviews (review_text VARIANT);
CREATE OR REPLACE TABLE yelp_businesses (business_text VARIANT);

-- Loading data from S3
COPY INTO yelp_reviews
FROM 's3://bucket-name/yelp/'
CREDENTIALS = (AWS_KEY_ID = '******' AWS_SECRET_KEY = '******')
FILE_FORMAT = (TYPE = JSON);

COPY INTO yelp_businesses
FROM 's3://bucket-name/yelp/yelp_academic_dataset_business.json'
CREDENTIALS = (AWS_KEY_ID = '******' AWS_SECRET_KEY = '******')
FILE_FORMAT = (TYPE = JSON);
```

### 4. Sentiment Analysis with Python UDF
- Created a User-Defined Function in Snowflake using Python
- Utilized VaderSentiment library for sentiment analysis
```sql
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
        sentiment_analyzer.analyzer = SentimentIntensityAnalyzer()
    scores = sentiment_analyzer.analyzer.polarity_scores(text)
    if scores['compound'] >= 0.05:
        return 'Positive'
    elif scores['compound'] <= -0.05:
        return 'Negative'
    else:
        return 'Neutral'
$$;
```

### 5. Data Transformation
- Converted JSON data into structured tables for analysis
```sql
-- Creating structured tables from JSON data
CREATE OR REPLACE TABLE tbl_yelp_reviews AS
SELECT 
    review_text:business_id::STRING AS business_id,
    review_text:user_id::STRING AS review_user_id,
    review_text:date::DATE AS review_date,
    review_text:stars::NUMBER AS review_stars,
    review_text:text::STRING AS review_text,
    analyze_sentiment(review_text) AS review_sentiment
FROM yelp_reviews;

CREATE OR REPLACE TABLE tbl_yelp_businesses AS
SELECT 
    business_text:business_id::STRING AS business_id,
    business_text:name::STRING AS business_name,
    business_text:city::STRING AS business_city,
    business_text:state::STRING AS business_state,
    business_text:stars::NUMBER AS business_stars,
    business_text:review_count::NUMBER AS business_review_count,
    business_text:categories::STRING AS business_categories
FROM yelp_businesses;
```

### 6. Data Analysis with SQL
The project explores several business questions through SQL queries:

1. **Businesses by Category**
```sql
WITH cte AS (
    SELECT business_id, trim(cat.value) AS business_cat
    FROM tbl_yelp_businesses,
    LATERAL split_to_table(business_categories,',') cat
)
SELECT business_cat, COUNT(*) no_of_business
FROM cte
GROUP BY business_cat
ORDER BY no_of_business DESC
LIMIT 10;
```

2. **Top Users Reviewing Restaurants**
```sql
SELECT r.review_user_id, COUNT(DISTINCT r.business_id) no_of_businesses
FROM tbl_yelp_reviews r
INNER JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
WHERE b.business_categories ILIKE '%restaurant%'
GROUP BY r.review_user_id
ORDER BY no_of_businesses DESC
LIMIT 10;
```

3. **Popular Business Categories by Review Count**
```sql
WITH cte AS (
    SELECT business_id, trim(cat.value) AS business_cat
    FROM tbl_yelp_businesses,
    LATERAL split_to_table(business_categories,',') cat
)
SELECT c.business_cat, COUNT(*) AS review_count
FROM cte c
JOIN tbl_yelp_reviews r ON c.business_id = r.business_id
GROUP BY c.business_cat
ORDER BY review_count DESC;
```

4. **Recent Reviews by Business**
```sql
SELECT b.business_name, r.review_date, r.review_text
FROM tbl_yelp_reviews r
JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY r.business_id ORDER BY r.review_date DESC) <= 3;
```

5. **Monthly Review Trends**
```sql
SELECT MONTH(review_date) AS review_month, COUNT(*) AS number_of_reviews
FROM tbl_yelp_reviews
GROUP BY review_month
ORDER BY number_of_reviews DESC;
```

6. **Five-Star Review Percentage by Business**
```sql
SELECT 
    b.business_name,
    COUNT(*) AS total_reviews,
    COUNT(CASE WHEN r.review_stars = 5 THEN 1 END) AS five_star_reviews,
    (COUNT(CASE WHEN r.review_stars = 5 THEN 1 END) * 100.0 / COUNT(*)) AS percent_five_star
FROM tbl_yelp_reviews r
JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
GROUP BY b.business_name, b.business_id
HAVING COUNT(*) >= 100
ORDER BY percent_five_star DESC;
```

7. **Top Reviewed Businesses by City**
```sql
SELECT 
    b.business_city,
    b.business_name,
    COUNT(*) AS total_reviews
FROM tbl_yelp_reviews r
JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
GROUP BY b.business_city, b.business_name, b.business_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY b.business_city ORDER BY COUNT(*) DESC) <= 5;
```

8. **Average Rating for Heavily Reviewed Businesses**
```sql
SELECT 
    AVG(r.review_stars) AS average_rating
FROM tbl_yelp_reviews r
JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
GROUP BY b.business_id
HAVING COUNT(*) >= 100;
```

9. **Top Reviewers and Their Reviewed Businesses**
```sql
WITH top_users AS (
    SELECT review_user_id
    FROM tbl_yelp_reviews
    GROUP BY review_user_id
    ORDER BY COUNT(*) DESC
    LIMIT 10
)
SELECT DISTINCT 
    r.review_user_id,
    b.business_id,
    b.business_name
FROM tbl_yelp_reviews r
JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
WHERE r.review_user_id IN (SELECT review_user_id FROM top_users)
ORDER BY r.review_user_id;
```

10. **Businesses with Highest Positive Sentiment**
```sql
SELECT 
    b.business_id,
    b.business_name,
    COUNT(*) AS positive_reviews
FROM tbl_yelp_reviews r
JOIN tbl_yelp_businesses b ON r.business_id = b.business_id
WHERE r.review_sentiment = 'Positive'
GROUP BY b.business_id, b.business_name
ORDER BY positive_reviews DESC
LIMIT 10;
```

## Alternative Approach
If you don't want to use AWS S3, you can directly upload files to Snowflake using the web interface:
1. Create tables with the appropriate schema
2. Use the "Load Data" option in Snowflake
3. Browse and select your files
4. Choose the target table
5. Load the data

## Performance Considerations
- Using a larger Snowflake warehouse (e.g., Large or X-Large) significantly improves processing time
- Splitting the large JSON file into smaller chunks enables parallel processing
- Using appropriate indexes and optimization techniques in SQL queries improves performance

## Future Enhancements
- Implement more advanced NLP techniques for sentiment analysis
- Create a dashboard for visualizing the insights
- Add time-series analysis to track sentiment trends over time
- Incorporate demographic data for more nuanced analysis

## Conclusion
This project demonstrates a complete data analytics pipeline, from data ingestion and transformation to advanced analysis using SQL and Python. The insights gained from this analysis can help businesses understand customer sentiment and improve their services accordingly.
