# functions
source("https://raw.githubusercontent.com/timriffe/covid_age/master/Automation/00_Functions_automation.R")

# assigning Drive credentials in the case the script is verified manually  
if (!"email" %in% ls()){
  email <- "kikepaila@gmail.com"
}

# Drive credentials
drive_auth(email = email)
gs4_auth(email = email)

# info country and N drive address
ctr <- "New Zealand"
dir_n <- "N:/COVerAGE-DB/Automation/Hydra/"

# TR: pull urls from rubric instead 
rubric_i <- get_input_rubric() %>% filter(Short == "NZ")
ss_i     <- rubric_i %>% dplyr::pull(Sheet)
ss_db    <- rubric_i %>% dplyr::pull(Source)

# TR:
# current operation just appends cases. I'd prefer to re-tabulate the full case history from the spreadsheet.

# reading data from Montreal and last date entered 
db_drive <- get_country_inputDB("NZ")

last_date_drive <- db_drive %>% 
  mutate(date_f = dmy(Date)) %>% 
  dplyr::pull(date_f) %>% 
  max()

# reading data from the website 
### source
m_url <- "https://www.health.govt.nz/our-work/diseases-and-conditions/covid-19-novel-coronavirus/covid-19-data-and-statistics/covid-19-case-demographics"

# reading date of last update
html      <- read_html(m_url)
date_text <-
  html_nodes(html, xpath = '//*[@id="node-10866"]/div[2]/div/div/p[1]') %>%
  html_text()
loc_date1 <- str_locate(date_text, "Last updated ")[2] + 4
loc_date2 <- str_length(date_text[1])

date_f  <- str_sub(date_text, loc_date1, loc_date2) %>% 
  str_trim() %>% 
  str_replace("\\.", "") %>% 
  dmy()

if (date_f > last_date_drive){

  ####################################
  # all cases from case-based database
  ####################################
  root <- "https://www.health.govt.nz"
  html <- read_html(m_url)
  url1 <- html_nodes(html, xpath = '//*[@id="node-10866"]/div[2]/div/div/p[13]/a') %>%
    html_attr("href")
  
  db_c <- read_csv(paste0(root, url1)) %>% 
    as_tibble()
  
  db_c2 <- 
    db_c %>% 
    select(date = 1,
           age_gr = 4,
           Sex) %>% 
    mutate(date_f = ymd(date))

  unique(db_c2$age_gr)
  
  db_c3 <- db_c2 %>% 
    separate(age_gr, c("Age", "trash"), sep = " to ") %>% 
    mutate(Age = case_when(Age == "90+" ~ "90",
                           TRUE ~ Age))
    unique(db_c3$Age)
  
  ages <-  suppressWarnings(as.integer(unique(db_c3$Age))) %>% sort() %>% as.character()
  dates <- unique(db_c3$date_f) %>% sort()
  
  db_c4 <- db_c3 %>% 
    group_by(date_f, Age, Sex) %>% 
    summarise(new = n()) %>% 
    ungroup() %>% 
    mutate(Sex = case_when(Sex == "Male" ~ "m", 
                           Sex == "Female" ~ "f", 
                           TRUE ~ "UNK")) %>% 
    tidyr::complete(date_f = dates, Sex = c("f", "m", "UNK"), Age = ages, fill = list(new = 0)) %>% 
    group_by(Sex, Age) %>% 
    mutate(Value = cumsum(new)) %>% 
    arrange(date_f, Sex, Age) %>% 
    ungroup() %>% 
    select(-new)

  db_c_sex <- db_c4 %>% 
    group_by(date_f, Age) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    mutate(Sex = "b") %>% 
    filter(Age != "UNK")
  
  db_c_age <- db_c4 %>% 
    group_by(date_f, Sex) %>% 
    summarise(Value = sum(Value)) %>% 
    ungroup() %>% 
    mutate(Age = "TOT") %>% 
    filter(Sex != "UNK")
  
  db_c5 <- db_c4 %>% 
    filter(Age != "UNK" & Sex != "UNK") %>% 
    bind_rows(db_c_sex, db_c_age) 
  
  unique(db_c5$Sex)
  unique(db_c5$Age)
  
  db_c6 <- db_c5 %>% 
    mutate(Country = "New Zealand",
           Region = "All",
           Date = paste(sprintf("%02d",day(date_f)),
                        sprintf("%02d",month(date_f)),
                        year(date_f),
                        sep="."),
           Code = paste0("NZ",Date),
           Metric = "Count",
           Measure = "Cases",
           AgeInt = case_when(Age == "90" ~ 15,
                              Age == "TOT" ~ NA_real_,
                              TRUE ~ 10)) %>% 
    arrange(date_f, Sex, Measure, suppressWarnings(as.integer(Age))) %>% 
    select(Country,Region, Code,  Date, Sex, Age, AgeInt, Metric, Measure, Value)
  
    
  
  
  ####################################
  # deaths by age from html table
  ####################################
  
  # cases and deaths by age for the last update
  m_url2 <- getURL(m_url)
  tables <- readHTMLTable(m_url2) 
  db_a <- tables[[3]] 
  db_s <- tables[[4]]
  
  db_a2 <- db_a %>% 
    as_tibble() %>% 
    select(Age = 1,
           Cases = 5,
           Deaths = 4) %>% 
    mutate(Cases = as.numeric(as.character(Cases)),
           Deaths = as.numeric(as.character(Deaths)),
           Deaths = replace_na(Deaths, 0)) %>% 
    separate(Age, c("Age", "trash"), sep = " to ") %>% 
    mutate(Age = case_when(Age == "90+" ~ "90",
                           Age == "Total" ~ "TOT",
                           TRUE ~ Age),
           Sex = "b") %>% 
    gather(Cases, Deaths, key = "Measure", value = "Value") %>% 
    select(-trash)
  
  db_s2 <- db_s %>% 
    as_tibble() %>% 
    select(Sex = 1,
           Cases = 5,
           Deaths = 4) %>% 
    mutate(Sex = case_when(Sex == "Female" ~ "f",
                           Sex == "Male" ~ "m",
                           Sex == "Total" ~ "b",
                           TRUE ~ "UNK"),
           Age = "TOT") %>% 
    gather(Cases, Deaths, key = "Measure", value = "Value") %>% 
    mutate(Value = as.numeric(Value)) %>% 
    filter(Sex != "UNK",
           Sex != "b")
    
  

  db_as <- bind_rows(db_a2, db_s2) %>% 
    mutate(AgeInt = case_when(Age == "90" ~ 15,
                              Age == "TOT" ~ NA_real_,
                              TRUE ~ 10))
  
  
  # tests by age and sex
  test_url <- "https://www.health.govt.nz/our-work/diseases-and-conditions/covid-19-novel-coronavirus/covid-19-data-and-statistics/testing-covid-19"
  test_url2 <- getURL(test_url)
  tables_test <- readHTMLTable(test_url2) 
  db_ta <- tables_test[[10]] 
  db_ts <- tables_test[[11]] 
  
  
  db_ta2 <- db_ta %>% 
    as_tibble() %>% 
    select(Age = 1,
           Value = 2) %>% 
    filter(Age != "Unknown") %>% 
    mutate(Value = as.numeric(Value)) %>% 
    separate(Age, c("Age", "trash"), sep = " to ") %>% 
    mutate(Age = case_when(Age == "80+" ~ "80",
                           Age == "Total" ~ "TOT",
                           TRUE ~ Age),
           Sex = "b") %>% 
    select(-trash)
  
  db_ts2 <- db_ts %>% 
    as_tibble() %>% 
    select(Sex = 1,
           Value = 2) %>% 
    mutate(Sex = case_when(Sex == "Female" ~ "f",
                           Sex == "Male" ~ "m",
                           Sex == "Total" ~ "b",
                           TRUE ~ "UNK"),
           Age = "TOT") %>% 
    filter(Sex != "UNK",
           Sex != "b") %>% 
    mutate(Value = as.numeric(Value))
  
  db_tas <- bind_rows(db_ta2, db_ts2) %>% 
    mutate(AgeInt = case_when(Age == "80" ~ 25,
                              Age == "TOT" ~ NA_real_,
                              TRUE ~ 10),
           Measure = "Tests")
  
  
  db_last_update <- bind_rows(db_as, db_tas) %>% 
    mutate(Country = "New Zealand",
           Region = "All",
           Date = paste(sprintf("%02d",day(date_f)),
                        sprintf("%02d",month(date_f)),
                        year(date_f),
                        sep="."),
           Code = paste0("NZ",Date),
           Metric = "Count")
  
  # back up of deaths and tests out of csv
  ########################################
  
  db_dv1 <- db_drive %>% 
    filter(Measure != "Cases") %>% 
    select(-Short)
  
  # combinations in the no-case base
  db_in <- db_dv1 %>% 
    select(Age, Sex, Measure, Date) %>% 
    mutate(already = 1)
    
  # combinations in the last_update
  db_lu <- 
    db_last_update %>% 
    filter(Measure != "Cases") %>% 
    select(Age, Sex, Measure, Date)
  
  # new stuff
  db_nw <- 
    db_lu %>% 
    left_join(db_in) %>% 
    filter(is.na(already)) %>% 
    select(-already) %>% 
    left_join(db_last_update)
  
  # new no-case base
  db_drive_out <- bind_rows(db_dv1, db_nw)
  
  # saving no cases info in Drive
  write_sheet(db_drive_out,
              ss = ss_i,
              sheet = "database")

  # filling missing dates between equal deaths
  ############################################

  db_dh <- 
    db_drive_out %>% 
    filter(Measure == "Deaths") %>% 
    mutate(date_f = dmy(Date)) %>% 
    select(date_f, Sex, Age, AgeInt, Metric, Measure, Value)
    
  db_dh2 <- 
    db_dh %>% 
    group_by(Age, Value) %>% 
    mutate(Val2 = mean(Value),
           orig = min(date_f),
           dest = max(date_f)) %>% 
    arrange(Age, date_f) %>% 
    ungroup() %>% 
    filter(date_f == orig | date_f == dest) %>% 
    mutate(wtf = case_when(date_f == orig ~ "origin",
                           date_f == dest ~ "destin"))
    
  combs <- db_dh2 %>% 
    select(Sex, Age, AgeInt, Metric, Measure, Val2) %>% 
    unique()
  
  db_filled1 <- NULL
  for(i in 1:dim(combs)[1]){
    a <- combs[i,2] %>% dplyr::pull()
    s <- combs[i,1] %>% dplyr::pull()
    v <- combs[i,6] %>% dplyr::pull()
    db_dh3 <- 
      db_dh2 %>% 
      filter(Age == a,
             Sex == s,
             Value == v)
    
    d1 <- min(db_dh3$date_f)
    d2 <- max(db_dh3$date_f)
    
    db_dh4 <- db_dh3 %>% 
      tidyr::complete(date_f = seq(d1, d2, "1 day"), Sex, Age, AgeInt, Metric, Measure, Value)
    
    db_filled1 <- db_filled1 %>% 
      bind_rows(db_dh4)
  }
  
  # keep dates in which the 11 age groups have information all together
  
  date_lupdate <- 
    db_last_update %>% 
    mutate(date_f = dmy(Date)) %>% 
    select(date_f) %>%
    unique() %>% 
    dplyr::pull()
  
  db_deaths_out <- db_filled1 %>% 
    select(date_f, Sex, Age, AgeInt, Metric, Measure, Value) %>% 
    filter(date_f != date_lupdate) %>% 
    group_by(date_f) %>% 
    filter(n() == 11) %>% 
    mutate(Country = "New Zealand",
           Region = "All",
           Date = paste(sprintf("%02d",day(date_f)),
                        sprintf("%02d",month(date_f)),
                        year(date_f),
                        sep="."),
           Code = paste0("NZ",Date),
           Metric = "Count")
  
  
  
  # putting together cases database, last update, and deaths
  ########################################################
  
  out <- bind_rows(db_c6, db_last_update, db_deaths_out) %>% 
    mutate(date_f = dmy(Date)) %>% 
    arrange(date_f, Sex, Measure, suppressWarnings(as.integer(Age))) %>% 
    select(Country,Region, Code,  Date, Sex, Age, AgeInt, Metric, Measure, Value)
  
  # view(db_all)
  
  #### saving database in N Drive ####
  ####################################
  
  write_rds(out, paste0(dir_n, ctr, ".rds"))
  log_update(pp = ctr, N = nrow(out))
  
  
  #### uploading metadata to N: Drive ####
  ########################################

  data_source1 <- paste0(dir_n, "Data_sources/", ctr, "/all_cases_",today(), ".csv")
  data_source2 <- paste0(dir_n, "Data_sources/", ctr, "/day_age",today(), ".csv")
  data_source3 <- paste0(dir_n, "Data_sources/", ctr, "/day_sex",today(), ".csv")
  data_source4 <- paste0(dir_n, "Data_sources/", ctr, "/tests_age",today(), ".csv")
  data_source5 <- paste0(dir_n, "Data_sources/", ctr, "/tests_sex",today(), ".csv")
  
  data_source <- c(data_source1,
                   data_source2,
                   data_source3,
                   data_source4,
                   data_source5)
  
  write_csv(db_c, data_source1)
  write_csv(db_a, data_source2)
  write_csv(db_s, data_source3)
  write_csv(db_ta, data_source4)
  write_csv(db_ts, data_source5)
  
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
  
} else if (date_f == last_date_drive) {
  log_update(pp = ctr, N = 0)
}

  
  
  
  
  
  
  
  
  
  
  
  
  
  