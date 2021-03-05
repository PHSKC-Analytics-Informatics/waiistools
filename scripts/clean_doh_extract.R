#This script takes a new DOH IIS extract and does some cleaning/reformatting.
# The biggest missing step is cleaning up addresses and subsequently determining who should be considered a King County resident.
# TODO: move the KC resident determination to this code

library('data.table')
county = 'PHSKC'
dirr = "" #The file directory where the WAIIS extract lives
fff = list.files(dirr, pattern = 'csv')
ts = as.Date(substr(fff,6,15), format = '%Y-%m-%d')
print(fff[which.max(ts)])
a = file.path(dirr, fff[which.max(ts)])

dat = fread(a)

#This section (lines ~11 - 34) is mostly about backwards compatibility with data structure before DOH started providing downloads
cb_headers = c("Patient ID", "First Name", "Middle Name", "Last Name", "Birthday",
               "Guardian F.N.", "Phone Number", "VFC Eligible", "Patient Facility",
               "Vaccine", "Vacc. Date", "Dose Size", "Mfg. Code", "Lot", "Funding",
               "VFC Eligible", "Historical", "Decremented", "Vaccinator", "Vaccine Facility",
               "Date VIS Form Given", "VIS Publication Date", "Reporting Method",
               "check_me", "Race", "ZIP", "striked")

#fix some date columns
for(ddd in c('RecipientDateOfBirth', 'RecipientDateOfBirth', 'AdministrationDate')){
  dat[, (ddd) := as.Date(get(ddd), format = '%d%b%Y')]
}

#Time columns
dat[, WaiisEntryDate := as.POSIXct(WaiisEntryDate, format = '%d%b%Y:%H:%M:%S')]
dat[is.na(WaiisEntryDate), WaiisEntryDate := as.POSIXct(WaiisInsertDate, format = '%d%b%Y:%H:%M:%S')]
dat[is.na(WaiisEntryDate), WaiisEntryDate := as.POSIXct(AdministrationDate)]

#Standardize names (via duplicate columns)
old = c('RecipientID', 'RecipientNameFirst', "RecipientNameMiddle", "RecipientNameLast", "RecipientDateOfBirth", 'AdministrationDate', 'AdministeredAtLocation', 'LotNumber', 'MVX', "RecipientAddressZipCode")
new = c("Patient ID", "First Name", "Middle Name", "Last Name", "Birthday", "Vacc. Date", 'Vaccine Facility', 'Lot', 'Mfg. Code', 'ZIP')
for(i in seq_along(old)) dat[, (new[i]) := get(old[i])]

dat = dat[!(tolower(VaccinationRefusal) == 'yes'),]

#make race variable
dat[, Race := IISRace1]
for(ir in paste0('IISRace', 2:6)){
  dat[(!is.na(get(ir)) & get(ir) != Race & get(ir) != 6) & !is.na(Race), Race := 8] #if new race is different than existing race (excluding other), make multi racial
  dat[is.na(Race) & !is.na(get(ir)), Race := get(ir)]
}

#convert to factor
dat[, Race := factor(Race,
                     c(1,2,4,5,6, 7, 8, 9),
                     c('White', 'Black or African American', 'Asian','American Indian or Alaska Native', 'Other', 'Native Hawaiian or Other Pacific Islander', 'More than 1 race specified', 'Not specifically determined'))]
dat[is.na(Race), Race := 'Not specifically determined']
dat[, Race := factor(Race,
                        c('Not specifically determined', 'Other','White', 'Black or African American', 'Asian','American Indian or Alaska Native','Native Hawaiian or Other Pacific Islander', 'More than 1 race specified'),
                        c('Not specifically determined', 'Other','White', 'Black or African American', 'Asian','American Indian or Alaska Native','Native Hawaiian or Other Pacific Islander', 'More than 1 race specified'))]

#add ethnicity
dat[, hispanic := factor(RecipientEthnicity, c('2186-5', '2135-2', 'UNK'), c('Not Hispanic', 'Hispanic', 'Unknown'))]

#make Race reflect the last observation
setorder(dat, WaiisEntryDate)
last_valid_race = function(x){
  x = na.omit(x)

  if(length(x) == 0) return('Not specifically determined')

  good = x[!x %in% c('Other', 'Not specifically determined')]
  if(length(good)>0) return(last(good))

  okay = x[!x %in% 'Not specifically determined']
  if(length(okay)>0) return(last(okay))

  return('Not specifically determined')

}

dat[, Race := last_valid_race(Race), `Patient ID`]

#make ethnicity reflect the last valid observation
last_valid = function(x){
  if(all(is.na(x))) return(unique(x))

  return(last(na.omit(x)))
}
setorder(dat, WaiisEntryDate)
dat[hispanic == 'Unknown', hispanic := NA]
dat[, hispanic := last_valid(hispanic), `Patient ID`]
dat[is.na(hispanic), hispanic := 'Unknown']

#make ZIP code reflect the last dose-- expand to addresses later
setorder(dat, WaiisEntryDate)
dat[, ZIP := last_valid(ZIP), `Patient ID`]

#make Birthday reflect the last dose-- expand to addresses later
setorder(dat, WaiisEntryDate)
dat[, Birthday := last_valid(Birthday)]

#remove duplicates
setorder(dat, `Patient ID`, `Vacc. Date`, WaiisEntryDate)

#Two passes
for(i in 1:2){
  print(nrow(dat))
  dat[, span :=  shift(`Vacc. Date`, type = 'lead') - `Vacc. Date`, by = `Patient ID`]
  dat[is.na(span), span := Inf]
  dat = dat[span >=6 ]
  dat[, span := NULL]
}

#Do a second cleaning by vaccine mfg
dat[, Manufacturer := factor(CVX, c(207, 208,210,212), c('Moderna', 'Pfizer', 'AstraZeneca', 'J&J/Janssen'))]
dat[is.na(Manufacturer), Manufacturer := factor(`Mfg. Code`, c('PFR', 'MOD'), c('Pfizer', 'Moderna'))]
dat[, Manufacturer := as.numeric(Manufacturer)]

#if mfg is missing, but there is another dose, use that one
dat[, Manufacturer := nafill(Manufacturer, 'locf'), by = `Patient ID`]
dat[, Manufacturer := nafill(Manufacturer, 'nocb'), by = `Patient ID`]
dat[, Manufacturer := factor(Manufacturer, 1:4, c('Moderna', 'Pfizer', 'AstraZeneca', 'J&J/Janssen'))]

dat[, ndoses := .N, `Patient ID`]

#fix 2 dose series
bad2s = dat[ndoses>2 & Manufacturer %in% c('Moderna', 'Pfizer')]
bad2s[, d1 := min(`Vacc. Date`), `Patient ID`] #when did dose 1 occur
bad2s[, dif := `Vacc. Date` - d1] #diff in days from dose 1
bad2s[Manufacturer == 'Moderna', dif2 := abs(dif - 28)] #how long from the ideal time frame from moderna
bad2s[Manufacturer == 'Pfizer', dif2 := abs(dif - 21)] #how long from the ideal time frame from pfizer
keepers = c(bad2s[dif == 0, VaccinationEventId], bad2s[dif!=0, VaccinationEventId[which.min(dif2)], `Patient ID`][,V1]) #keep first dose, and the other dose that best matches the span
droppers = setdiff(bad2s[, VaccinationEventId], keepers)
dat = dat[!VaccinationEventId %in% droppers, ]

#fix one dose series
#this will miss people who coded for different vaccines. E.g. one dose of pfz and one of J&J
bad1s = dat[Manufacturer %in% 'J&J/Janssen' & ndoses>1, VaccinationEventId[which.min(`Vacc. Date`)], by = `Patient ID`] #first recorded dose is kept
droppers = setdiff(dat[Manufacturer %in% 'J&J/Janssen' & ndoses>1, VaccinationEventId], bad1s) #get the lsit of other doses
dat = dat[!VaccinationEventId %in% droppers] #drop the others

print(nrow(dat))
dat[, report_date := as.Date(gsub(county, "", basename(tools::file_path_sans_ext(a))), format = '%Y-%m-%d')]

saveRDS(dat, file.path(dirname(a), 'doh_phskc_extract.rds'))
