# DNS Lookup

MariaDB SQL Stored Procedures for SRV based DNS lookup using PowerDNS 4.2

# How to install
This is really intended for internal ASL use, but it's provided as it may be usefull for the community.  

This is using pdns server 4.2 and needs access to the ASL databse on the dns server.

## First install and configure pdns on the server.  
### You will need to add the NS records and RR records to the toplevel domain

#### gmysql.conf
gmysql.conf 
  # config for pdns
  # MySQL Configuration
  #
  # Launch gmysql backend
  launch+=gmysql
  # gmysql parameters
  gmysql-host=127.0.0.1
  gmysql-port=3306
  gmysql-dbname=allstar
  gmysql-user=root
  gmysql-password=ButtPlugs!!
  gmysql-dnssec=yes
  # gmysql-socket=
  #custom queries defined 
  gmysql-basic-query=CALL DNS_basic_query(?, ?)
  gmysql-id-query = CALL  DNS_id_query(?, ?, ?)
  gmysql-any-id-query = CALL DNS_any_id_query(?, ?)
  gmysql-any-query = CALL DNS_any_query(?)


#### now insert the tables into the allstar database

  mysql -u allstar -p -u allstar \<pdns-42-schema.sql 

### now add the sprocs
   mysql -u allstar -p -u allstar \<DNS\_basic.sql

## Test 
Test dns lookups for TXT, SRV and A records

