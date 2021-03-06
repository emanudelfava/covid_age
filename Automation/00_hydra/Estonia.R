library(here)
source(here("Automation/00_Functions_automation.R"))

# assigning Drive credentials in the case the script is verified manually  
if (!"email" %in% ls()){
  email <- "e.delfava@gmail.com"
}

# info country and N drive address
ctr <- "Estonia"
dir_n <- "N:/COVerAGE-DB/Automation/Hydra/"

# Drive credentials
drive_auth(email = email)
gs4_auth(email = email)

cols_in <- cols(
  id = col_character(),
  Gender = col_character(),
  AgeGroup = col_character(),
  Country = col_character(),
  County = col_character(),
  ResultValue = col_character(),
  StatisticsDate = col_date(format = ""),
  ResultTime = col_datetime(format = ""),
  AnalysisInsertTime = col_datetime(format = "")
)

db <- read_csv("https://opendata.digilugu.ee/opendata_covid19_test_results.csv", col_types = cols_in)

db2 <- db %>% 
  rename(Sex = Gender) %>% 
  tidyr::separate(AgeGroup, c("Age","age2"), "-") %>% 
  mutate(Test = 1,
         Case = ifelse(ResultValue == "P", 1, 0),
         date_f = as.Date(ResultTime),
         Sex = case_when(Sex == 'N' ~ 'f',
                         Sex == 'M' ~ 'm',
                         TRUE ~ 'UNK'),
         Age = readr::parse_number(Age),
         Age = replace_na(Age, "UNK")) %>% 
  group_by(date_f, Age, Sex) %>% 
  summarise(Cases = sum(Case),
            Tests = sum(Test)) %>% 
  ungroup() %>% 
  pivot_longer(Cases:Tests, names_to = "Measure", values_to = "new")

db3 <- db2 %>% 
  tidyr::complete(date_f = unique(db2$date_f), Sex = unique(db2$Sex), Age = unique(db2$Age), Measure, fill = list(new = 0)) %>% 
  group_by(Sex, Age, Measure) %>% 
  mutate(Value = cumsum(new)) %>% 
  arrange(date_f, Sex, Measure, Age) %>% 
  ungroup() 

# TR: these steps aren't necessary at the data entry stage.
# The R pipeline does all this.
# db4 <- db3 %>% 
#   group_by(date_f, Sex, Measure) %>% 
#   summarise(Value = sum(Value)) %>% 
#   mutate(Age = "TOT") %>%
#   ungroup() 
# 
 db5 <- db3 %>% 
   group_by(date_f, Measure) %>% 
   summarise(Value = sum(Value)) %>% 
   mutate(Sex = "b", Age = "TOT") %>% 
   ungroup() 
# 
 # db6 <- db3 %>% 
 #   group_by(date_f, Age, Measure) %>% 
 #   summarise(Value = sum(Value)) %>% 
 #   mutate(Sex = "b") %>% 
 #   ungroup() 

db_all <- bind_rows(db3, db5) %>% 
  filter(Age != "UNK",
         Sex != "UNK") %>%
  mutate(Region = "All",
         Date = paste(sprintf("%02d", day(date_f)),
                      sprintf("%02d", month(date_f)),
                      year(date_f), sep = "."),
         Country = "Estonia",
         Code = paste0("EE_", Date),
         AgeInt = case_when(Age == "TOT" | Age == "UNK" ~ NA_real_, 
                            Age == "85" ~ 20,
                            TRUE ~ 5),
         Metric = "Count") %>% 
  select(Country, Region, Code, Date, Sex, Age, AgeInt, Metric, Measure, Value) %>% 
  sort_input_data()

###########################
#### Saving data in N: ####
###########################

# database
write_rds(db_all, paste0(dir_n, ctr, ".rds"))
log_update(pp = "Estonia", N = nrow(db_all))

# datasource
data_source <- paste0(dir_n, "Data_sources/", ctr, "/cases&tests_",today(), ".csv")

write_csv(db, data_source)

zipname <- paste0(dir_n, 
                  "Data_sources/", 
                  ctr,
                  "/", 
                  ctr,
                  "_data_",
                  today(), 
                  ".zip")

zipr(zipname, 
     data_source, 
     recurse = TRUE, 
     compression_level = 9,
     include_directories = TRUE)

# clean up file chaff
file.remove(data_source)

