# Load required packages
library(tidyverse)
library(ggplot2)
library(DT)
library(wesanderson)
library(viridis)
library(Hmisc)
library(tm)
library(wordcloud)
library(openxlsx)


# Read in IMDB Top 1000 Movies Dataset
movies <- read.csv("imdb_top_1000.csv")


# Explore data
head(movies)
summary(movies)
str(movies)


################################### CLEANING & PREPARING THE DATA ###################################

# Remove any possible duplicates
movies_unique <- distinct(movies)


# Remove unnecessary columns
movies_unique_cleaned <- subset(movies_unique, select = -c(Poster_Link))


# Clean "Released_Year" column
movies_unique_cleaned$Released_Year <- as.integer(movies_unique_cleaned$Released_Year)
# Received warning message: NAs introduced by coercion
# Display the rows where the release year is NA
non_numeric_release_year <- is.na(movies_unique_cleaned$Released_Year)
print(movies_unique_cleaned[non_numeric_release_year, ])
# Enter the correct release year of "Apollo 13"
movies_unique_cleaned[967, "Released_Year"] <- 1995


# Clean "Runtime" column
movies_unique_cleaned$Runtime <- as.integer(gsub("[^0-9]", "", movies_unique_cleaned$Runtime))


# Clean "Gross"(Revenue) column
movies_unique_cleaned$Gross <- as.integer(gsub(",", "", movies_unique_cleaned$Gross))


## Normalize "Certificate" column
count_table <- table(movies_unique_cleaned$Certificate) # Check what ratings we currently have
print(count_table)
# Define a named vector for the mapping of CBFC ratings to MPA ratings
CBFC_to_MPA <- c("G" = "PG",
                 "U" = "PG",
                 "GP" = "PG",
                 "TV-PG" = "PG",
                 "PG" = "PG",
                 "UA" = "PG-13",
                 "U/A" = "PG-13",
                 "16" = "PG-13",
                 "TV-14" = "PG-13",
                 "PG-13" = "PG-13",
                 "A" = "R",
                 "TV-MA" = "R",
                 "R" = "R",
                 "Approved" = "Unrated",
                 "Passed" = "Unrated",
                 "Unrated" = "Unrated",
                 " " = "Unrated", # Handling empty strings
                 NULL = "Unrated") # Handling NULL values
# Define a function to map CBFC film ratings to MPA film ratings
convert_to_american <- function(indian_rating) {
  return(CBFC_to_MPA[indian_rating]) # Map the Indian rating to American rating using the defined vector
}
# Apply the conversion function to the column
movies_unique_cleaned$Certificate <- sapply(movies_unique_cleaned$Certificate, convert_to_american)
# Convert NAs to "Unrated"
movies_unique_cleaned$Certificate[is.na(movies_unique_cleaned$Certificate)] <- "Unrated"


############################################# ANALYSIS #############################################

# Using the Wes Anderson color palettes for obvious reasons
wa1 <- wes_palette("Darjeeling2")
wa2 <- wes_palette("Darjeeling1")
wa3 <- wes_palette("FrenchDispatch")
wa4 <- wes_palette("IsleofDogs1")


######################### TEMPORAL ANALYSIS #########################

# How has the average IMDb rating of the top 1000 movies changed over the decades?
# Convert Released_Year to a factor with decades
movies_unique_cleaned$Decade <- cut(movies_unique_cleaned$Released_Year, 
                     breaks = seq(1910, 2020, by = 10), 
                     labels = seq(1910, 2010, by = 10), 
                     include.lowest = TRUE)
# Plot average IMDb rating over decades
ggplot(movies_unique_cleaned, aes(x = Decade, y = IMDB_Rating, group = 1)) +
  stat_summary(fun.data = "mean_cl_boot", geom = "line", color = wa2[2]) +
  stat_summary(fun.data = "mean_cl_boot", geom = "point", color = wa2[1], size = 3) +
  labs(title = "Average IMDb Rating of Top 1000 Movies Over the Decades",
       x = "Decade",
       y = "Average IMDb Rating") +
  theme_minimal()


# What is the distribution of movie runtimes over the years?
# Movie runtimes over the years
ggplot(movies_unique_cleaned, aes(Released_Year, Runtime)) + 
  geom_point(color = wa3[1]) + 
  geom_smooth(method = "loess", color = wa3[2]) + 
  labs(title = "Distribution of Movie Runtimes Over the Years",
       x = "Year Released",
       y = "Runtime (in minutes)") +
  theme_minimal() +
  xlim(min(movies_unique_cleaned$Released_Year) - 2, max(movies_unique_cleaned$Released_Year) + 2)


# Are there certain decades that produced more top 1000 rated movies?
# Create a vector with all the decades from 1910 to 2010
decades <- seq(1910, 2010, by = 10)
# Count the number of movies from each decade
decade_counts <- table(cut(movies_unique_cleaned$Released_Year, seq(1910, 2020, by = 10)))
# Add missing decades to the table
decade_counts <- c(decade_counts, rep(0, length(decades) - length(decade_counts)))
# Convert the counts to a data frame
decade_counts_df <- data.frame(Decade = as.character(decades), Count = as.numeric(decade_counts))
# Plot the representation of decades in the top 1000 movies
ggplot(decade_counts_df, aes(x = Decade, y = Count, fill = Decade)) +
  geom_bar(stat = "identity") +
  scale_fill_viridis(discrete = TRUE) +
  labs(title = "Representation of Each Decade in the Top 1000 Movies",
       x = "Decade",
       y = "Number of Movies") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))  # Rotate x-axis labels for better readability


########################### GENRE ANALYSIS ############################

# Which genres are most common among the top-rated movies?
# Split genres into separate rows
movies_genre_split <- movies_unique_cleaned %>%
  separate_rows(Genre, sep = ", ") %>%
  filter(!is.na(Genre))  # Remove rows with missing genre entries, if any
# Count the frequency of each individual genre
genre_counts <- table(movies_genre_split$Genre)
# Sort the genre counts in descending order
sorted_genre_counts <- sort(genre_counts, decreasing = TRUE)
# Select the top 5 most common genres
top_5_genres <- names(sorted_genre_counts)[1:5]
# Count the number of movies in the top 5 genres
top_5_genre_counts <- sum(sorted_genre_counts[1:5])
# Create a new data frame with the top 5 genres and their counts
top_5_genre_df <- data.frame(Genre = top_5_genres,
                             Count = as.numeric(sorted_genre_counts[1:5]))
# Create a new data frame for the "Other" category
other_genre_df <- data.frame(Genre = "Other",
                             Count = sum(sorted_genre_counts[6:length(sorted_genre_counts)]))
# Combine the top 5 genres and the "Other" category
final_genre_df <- rbind(top_5_genre_df, other_genre_df)
# Calculate percentages for each genre
final_genre_df <- final_genre_df %>%
  mutate(Percentage = (Count / sum(Count)) * 100)
# Create the pie chart
ggplot(final_genre_df, aes(x = "", y = Count, fill = Genre)) +
  geom_bar(stat = "identity", width = 1) +
  coord_polar("y", start = 0) +
  scale_fill_viridis(discrete = TRUE) +
  geom_text(aes(label = paste0(round(Percentage), "%")), 
            position = position_stack(vjust = 0.5)) +
  labs(title = "Distribution of Genres Among Top-Rated Movies",
       fill = "Genre") +
  theme_void() +
  theme(legend.position = "right")


# What is the average rating for each genre?
# Split genres into separate rows
movies_genre_split <- movies_unique_cleaned %>%
  separate_rows(Genre, sep = ", ") %>%
  filter(!is.na(Genre))  # Remove rows with missing genre entries, if any
# Group the data by genre and calculate the mean IMDb rating for each group
genre_avg_rating <- movies_genre_split %>%
  group_by(Genre) %>%
  summarise(Avg_Rating = round(mean(IMDB_Rating, na.rm = TRUE), 2)) 
# Print the result
datatable(genre_avg_rating, options = list(pageLength = 30, order = list(list(2, 'desc'))))


# Is there a correlation between the age rating of a movie and its genre?
# Create contingency table
contingency_table <- table(movies_genre_split$Genre, movies_genre_split$Certificate)
# Create heat map
ggplot(data = as.data.frame.table(contingency_table), aes(x = Var1, y = Var2, fill = Freq)) +
  geom_tile() +
  scale_fill_viridis() +
  labs(title = "Correlation between Movie Genre and Age Rating", x = "Genre", y = "Age Rating") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, vjust = 0.5, hjust = 0.5))


########################## DIRECTOR ANALYSIS ##########################

# Is there a correlation between a director's average movie rating and the number of 
# movies they have directed in the list?
# Calculate average movie rating and number of movies directed for each director
director_stats <- movies_unique_cleaned %>%
  group_by(Director) %>%
  summarise(Avg_Rating = round(mean(IMDB_Rating, na.rm = TRUE), 2),
            Num_Movies = n_distinct(Series_Title))
# Correlation analysis
correlation <- cor(director_stats$Avg_Rating, director_stats$Num_Movies)
# Visualization
ggplot(director_stats, aes(x = Num_Movies, y = Avg_Rating)) +
  geom_point(color = wa2[4]) +
  geom_smooth(method = "lm", se = FALSE, color = wa1[2]) +
  labs(title = "Correlation Between Director's Average Rating and Number of Movies Directed",
       x = "Number of Movies Directed",
       y = "Average Movie Rating") +
  theme_minimal() +
  xlim(0, max(director_stats$Num_Movies) + 1) +
  ylim(7.5, max(director_stats$Avg_Rating))
# Correlation coefficient
print(paste("Correlation coefficient:", correlation))


# Who are the top directors in terms of the number of movies in the top 1000 list?
# Print the table sorted by the number of movies in descending order
datatable(director_stats, options = list(pageLength = 15, order = list(list(3, 'desc'))))


############################ ACTOR ANALYSIS ############################

# Which actors appear most frequently in the top-rated movies?
# Split actors into separate rows
movies_actors_split <- movies_unique_cleaned %>%
  mutate(Actors = paste(Star1, Star2, Star3, Star4, sep = ", ")) %>%
  separate_rows(Actors, sep = ", ") %>%
  filter(!is.na(Actors))  # Remove rows with missing actor entries, if any
# Count the number of appearances for each actor
actor_counts <- movies_actors_split %>%
  group_by(Actors) %>%
  summarise(Appearances = n()) %>%
  arrange(desc(Appearances))
# Print the table sorted by the number of appearances in descending order
datatable(actor_counts, options = list(pageLength = 10))


# How does the number of movies each of the top 10 actors has starred in 
# relate to the average rating of those movies?
# Select top 10 actors based on appearances
top_actors <- head(actor_counts, 10)
# Filter movies associated with top 10 actors
movies_top_actors <- movies_actors_split %>%
  filter(Actors %in% top_actors$Actors)
# Calculate the average rating and number of movies for each actor
actor_summary <- movies_top_actors %>%
  group_by(Actors) %>%
  summarise(Avg_Rating = mean(IMDB_Rating, na.rm = TRUE),
            Num_Movies = n())
# Create a scatter plot for the relationship between number of movies and average rating
ggplot(actor_summary, aes(x = Num_Movies, y = Avg_Rating, label = Actors)) +
  geom_point(color = wa1[2], size = 3) +
  geom_text(hjust = -0.15, vjust = 0.3, size = 3) +
  labs(title = "Number of Movies vs. Average Rating for Top 10 Actors",
       x = "Number of Movies",
       y = "Average Rating") +
  theme_minimal() +
  xlim(9, 18) +
  ylim(7.5, 8.25)


####################### RATING & REVENUE ANALYSIS #######################

# Distribution of Revenue
# Create a histogram for the distribution of revenue
ggplot(movies_unique_cleaned, aes(x = Gross)) +
  geom_histogram(binwidth = 10000000, fill = wa2[2], color = "black") +
  scale_x_continuous(labels = scales::comma_format()) +  # Format x-axis labels
  labs(title = "Distribution of Revenue",
       x = "Gross Revenue",
       y = "Number of Movies") +
  theme_minimal()


# Is there a correlation between the IMDb rating and the money a movie earns?
# Create a scatter plot for IMDb rating vs. revenue
ggplot(movies_unique_cleaned, aes(x = IMDB_Rating, y = Gross)) +
  geom_point(color = wa3[4]) +  # Scatter plot
  geom_smooth(method = "lm", se = FALSE, color = wa3[2]) +  # Linear regression line
  scale_y_continuous(labels = scales::comma_format()) +
  labs(title = "IMDb Rating vs. Gross Revenue",
       x = "IMDb Rating",
       y = " Gross Revenue") +
  theme_minimal()


######################### OTHER ANALYSIS ###############################

# What age rating is most common?
# Number of movies in each age rating
ggplot(movies_unique_cleaned) + 
  geom_bar(aes(x = Certificate, fill = Certificate)) +
  scale_fill_manual(values = wa1, name = "Age Rating") +
  labs(title = "Number of Movies in Each Age Rating",
       x = "Age Rating",
       y = "Number of Movies") +
  theme_minimal() +
  ylim(0, 400)
# Filter the dataset to include only movies released after 1984
filtered_movies <- movies_unique_cleaned %>%
  filter(Released_Year > 1984)
# Create the visualization for movies released after 1984
ggplot(filtered_movies) + 
  geom_bar(aes(x = Certificate, fill = Certificate)) +
  scale_fill_manual(values = wa1, name = "Age Rating") +
  labs(title = "Number of Movies in Each Age Rating (After 1984)",
       x = "Age Rating",
       y = "Number of Movies") +
  theme_minimal() +
  ylim(0, 400)


# What are some common themes or topics that show up in the top rated movies?
# Create a word cloud of the most prevalent and meaningful words in the overview column
# Corpus
corpus <- Corpus(VectorSource(movies_unique_cleaned$Overview))
corpus <- tm_map(corpus, content_transformer(tolower))
corpus <- tm_map(corpus, removePunctuation)
corpus <- tm_map(corpus, removeNumbers)
corpus <- tm_map(corpus, removeWords, stopwords("english"))
# Term-Document Matrix
tdm <- TermDocumentMatrix(corpus)
# Convert TDM to a matrix
m <- as.matrix(tdm)
word_freqs <- sort(rowSums(m), decreasing = TRUE)
# Create the word cloud
wordcloud(words = names(word_freqs), freq = word_freqs, min.freq = 1,
          max.words = 50, random.order = FALSE, colors = brewer.pal(8, "Dark2"))

