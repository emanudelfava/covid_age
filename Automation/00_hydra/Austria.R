library(here)
source(here("Automation/00_Functions_automation.R"))

# assigning Drive credentials in the case the script is verified manually  
if (!"email" %in% ls()){
  email <- "kikepaila@gmail.com"
}

# info country and N drive address
ctr <- "Austria"
dir_n <- "N:/COVerAGE-DB/Automation/Hydra/"

drive_auth(email = email)
gs4_auth(email = email)

# TR: pull urls from rubric instead 
at_rubric <- get_input_rubric() %>% filter(Short == "AT")
ss_i   <- at_rubric %>% dplyr::pull(Sheet)
ss_db  <- at_rubric %>% dplyr::pull(Source)

# reading data from Austria and last date entered 
db_drive <- get_country_inputDB("AT")
db_drive2 <- db_drive %>% 
  mutate(date_f = dmy(Date))

last_date_drive <- max(db_drive2$date_f)

# loading data from the website 
data_source <- paste0(dir_n, "Data_sources/", ctr, "/", ctr, "_data_", today(), ".zip")
download.file("https://info.gesundheitsministerium.at/data/data.zip", data_source)

db_c_age <- read_csv2(unz(data_source, "Altersverteilung.csv"))
db_c_sex <- read_csv2(unz(data_source, "Geschlechtsverteilung.csv"))
db_d_age <- read_csv2(unz(data_source, "AltersverteilungTodesfaelle.csv"))
db_d_sex <- read_csv2(unz(data_source, "VerstorbenGeschlechtsverteilung.csv"))
db_tests <- read_csv2(unz(data_source, "AllgemeinDaten.csv"))

date_f <- db_c_age$Timestamp[1] %>% 
  str_sub(1,10) %>% 
  ymd()

d <- paste(sprintf("%02d", day(date_f)),
           sprintf("%02d", month(date_f)),
           year(date_f), sep = ".")

# verify if new data is not already included in Drive
if (date_f > last_date_drive){
  
  db_c_age2 <- db_c_age %>% 
    separate(Altersgruppe, c("Age", "trash"), sep = "-") %>% 
    mutate(Age = case_when(Age == "<5" ~ "0",
                           Age == ">84" ~ "85",
                           TRUE ~ Age),
           Metric = "Count",
           Sex = "b") %>% 
    rename(Value = Anzahl) %>% 
    select(Sex, Age, Metric, Value)
  
  db_c_sex2 <- db_c_sex %>% 
    rename(Value = "Anzahl in %") %>% 
    mutate(Sex = case_when(Geschlecht == "weiblich" ~ "f",
                           Geschlecht == "m?nnlich" ~ "m",
                           TRUE ~ "UNK"),
           Metric = "Fraction",
           Value = Value / 100,
           Age = "TOT") %>% 
    select(Sex, Age, Metric, Value)
  
  db_cases <- bind_rows(db_c_age2, db_c_sex2) %>% 
    mutate(Measure = "Cases")
  
  
  db_d_age2 <- db_d_age %>% 
    separate(Altersgruppe, c("Age", "trash"), sep = "-") %>% 
    mutate(Age = case_when(Age == "<5" ~ "0",
                           Age == ">84" ~ "85",
                           TRUE ~ Age),
           Metric = "Count",
           Sex = "b") %>% 
    rename(Value = Anzahl) %>% 
    select(Sex, Age, Metric, Value)
  
  db_d_sex2 <- db_d_sex %>% 
    rename(Value = "Anzahl in %") %>% 
    mutate(Sex = case_when(Geschlecht == "weiblich" ~ "f",
                           Geschlecht == "m?nnlich" ~ "m",
                           TRUE ~ "UNK"),
           Metric = "Fraction",
           Value = Value / 100,
           Age = "TOT") %>% 
    select(Sex, Age, Metric, Value)
  
  db_deaths <- bind_rows(db_d_age2, db_d_sex2) %>% 
    mutate(Measure = "Deaths")
  
  db_tests2 <- db_tests %>% 
    select(GesTestungen) %>% 
    rename(Value = GesTestungen) %>% 
    mutate(Sex = "b",
           Metric = "Count",
           Age = "TOT",
           Measure = "Tests")
    
  out <- bind_rows(db_deaths, db_cases, db_tests2) %>% 
    mutate(Country = "Austria",
           Region = "All",
           Code = paste0("AT", d),
           Date = d,
           AgeInt = case_when(Age == "0" ~ "5",
                              Age == "85" ~ "20",
                              Age == "TOT" ~ "",
                              TRUE ~ "10")) %>% 
    select(Country, Region, Code, Date, Sex, Age, AgeInt, Metric, Measure, Value)
  
  ############################################
  #### uploading database to Google Drive ####
  ############################################
  # This command append new rows at the end of the sheet
  sheet_append(out,
               ss = ss_i,
               sheet = "database")
  log_update(pp = ctr, N = nrow(out))
  
} else if (date_f == last_date_drive) {
  cat(paste0("no new updates so far, last date: ", date_f))
  log_update(pp = ctr, N = 0)
}

  
