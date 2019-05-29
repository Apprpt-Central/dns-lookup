# DNS Lookup

MariaDB SQL Stored Procedures for SRV based DNS lookup using PowerDNS 4.2
This provides access to the AllStar Link database via DNS.

## Overview 
This supports the following records under the subdomain of nodes.allstarlink.org:
* SRV
* TXT
* A

This is based on the AllStar Link DNS lookup standard provided on the wiki.  

## Example Queries 

### SRV
This is used to find the port and hostname of the node and if it's a remotebase

```
dig SRV _iax._udp.2020.nodes.allstarlink.org

; <<>> DiG 9.10.3-P4-Ubuntu <<>> SRV _iax._udp.2020.nodes.allstarlink.org
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 25251
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1452
;; QUESTION SECTION:
;_iax._udp.2020.nodes.allstarlink.org. IN SRV

;; ANSWER SECTION:
_iax._udp.2020.nodes.allstarlink.org. 30 IN SRV 10 10 4572 2020.nodes.allstarlink.org.
```
This returns the port, 4572 and the hostname of the server as 2020.nodes.allstarlink.org. 
If this was a remotebase the hostname would be returned as 2020.remotebase.nodes.allstarlink.org.

### A

This is used to resolve the hostname from the SRV into an IP address.
```
dig A 2020.nodes.allstarlink.org.

; <<>> DiG 9.10.3-P4-Ubuntu <<>> A 2020.nodes.allstarlink.org.
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 28603
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1452
;; QUESTION SECTION:
;2020.nodes.allstarlink.org.    IN      A

;; ANSWER SECTION:
2020.nodes.allstarlink.org. 30  IN      A       73.11.141.48
```

### TXT

The TXT record is optional, but gives debugging info about the status of the registration of a node.

```
dig TXT 2560.nodes.allstarlink.org

; <<>> DiG 9.10.3-P4-Ubuntu <<>> TXT 2560.nodes.allstarlink.org
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 23328
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1452
;; QUESTION SECTION:
;2560.nodes.allstarlink.org.    IN      TXT

;; ANSWER SECTION:
2560.nodes.allstarlink.org. 30  IN      TXT     "NN=2560" "RT=2019-05-29 08:12:33" "RB=0" "IP=173.82.59.253" "PIP=" "PT=4569" "RH=register-fnt"
```

The records returned are:

* NN - Node Number as seen in the database
* RT - Registration time as seen in the database converted to UTC from unixtime
* RB - Remote base 1 if true, 0 if not remote base
* IP - IP address of the node doing the registration via IAX2
* PIP - Proxy IP address if set
* PT - Port to connect to
* RH - Registration server hostname that processed the registration request

## Notes
In the event these records are not present the queries fallback on the normal pdns table layout.  This means static records can be defined in the normal pdns fields, and the pdnsutil command can provision/test these if needed.  This does open up the possibility that multiple A/SRV/TXT records can be defined, and the SQL/pdns will handle it, as it's valid.  Asterisk is expecting to see a single SRV and A record returned to it for a node number via DNS, so this may break asterisk if a static record is made and then a dynamic generated record is returned.

The records returned here are not aged out after 10 minuted like the nodeslist.  There is little point to this, as freshness can be queried via the TXT record.  In any event if a server is not updating it's registration, connections to and from it will fail, just as with the nodelist. 

## How to install
This is really intended for internal ASL use, but it's provided as it may be usefull for the community.  

This is using pdns server 4.2 and needs access to the ASL databse on the dns server.

## First install and configure pdns on the server.  

You will need to add the NS records and RR records to the toplevel domain, and an SOA record in the database too

* gmysql.conf
---

```
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

```

Now insert the tables into the allstar database if they don't exist:

```
mysql allstar --comments <pdns-42-schema.sql 
```

Now each stored procedure:
```
mysql allstar --comments <DNS_basic.sql
mysql allstar --comments <DNS_any_query.sql
mysql allstar --comments <DNS_any_id_query.sql
mysql allstar --comments <DNS_id_query.sql
```
## Test 
Test dns lookups for TXT, SRV and A records

## Authors

* **Bryan Fields** - [bryan@bryanfields.net](mailto:bryan@bryanfields.net)

## License

This project is licensed under the GNU Affero General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

* Tom for his help with the SRV records (who knew they existed!)
* Stacy for his help with the internals of asterisk


