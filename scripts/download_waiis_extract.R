#Given a username, credentials stored in keyring, and an output location, save any new versions of the wAIIS extract
library('RCurl')
library('keyring')
username = '' #SFTP username
output = "" #file path to transfer the SFTP file from
files <- getURL('sftp://sft.wa.gov', userpwd = paste0('username:',keyring::key_get('dohsftp',username)),
                           ftp.use.epsv = FALSE,dirlistonly = TRUE)
files = unlist(strsplit(files, '\\n'))

files = grep('PHSKC', files, value = T)

file_dates = as.Date(substr(files, 6,15), '%Y-%m-%d')

dlme = files[which.max(file_dates)]
if(!file.exists(file.path(output, dlme))){

  fileurl = paste0('sftp://sft.wa.gov/', files[which.max(file_dates)])
  userpwd = paste0('username:',keyring::key_get('dohsftp',username))
  writeBin(object = RCurl::getBinaryURL(url = fileurl, port = 22, userpwd = userpwd, dirlistonly = FALSE), con = file.path(output, dlme))
}
