START TRANSACTION;
DELIMITER //
DROP TRIGGER pdns //
CREATE TRIGGER pdns AFTER UPDATE ON user_Nodes FOR EACH ROW 
  BEGIN
   /* 
    This will build SRV,TXT, and A records into the 'records' table for power DNS
    for AllStarLink for any update on the user_Nodes row
    Copyright (C) 2019 Bryan Fields
    Bryan@bryanfields.net
    +1-727-409-1194

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License Version 3, 
    as published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

--------------------------- Revision History ----------------------------------
  2019-07-05      bfields     Inital prototype
  2019-07-08      bfields     A and TXT records working
  2019-07-09      bfields     Optomization and speedup, well under .010 seconds
  
 Note we need the following unique index on the records table.  We use the ttl for identifying generated records vs. static.  
  This means, never use the proc ttl here for static records or it will cause issues.   
ALTER TABLE records ADD CONSTRAINT nameTypeTTL UNIQUE KEY (name, type, ttl);    
*/

/*  Declare shit here before anything else */
/*
  proc_ttl here is used as a special key.  We first delete anything in the db with this ttl
  if you want to make static records in the DB they must use a different TTL than 30
  specialSubdomain is used to id the subdomain we're living under
  proc_domain_id should be the domain ID used in the records table for specialSubDomain
  proc_auth should be the default state of auth
  */
  

  DECLARE procPort varchar(6);
  DECLARE procProxy_IP varchar(20);
  DECLARE srvWeight int DEFAULT 10;
  DECLARE proc_domain_id INT DEFAULT 1;
  DECLARE proc_ttl INT DEFAULT 30;
  DECLARE proc_prio INT DEFAULT 11;
  DECLARE specialSubDomain varchar(64) DEFAULT 'nodes.allstarlink.org';






/* Select the stuff not in the user_Nodes table (proxy and port) from user_Servers */
SELECT udpport, proxy_ip INTO procPort, procProxy_IP from user_Servers where config_id = NEW.Config_ID;

/* Not needed, as they are set up in the DECLARE's and this is a _HUGE_ speedup
  SELECT  domains.id INTO proc_domain_id FROM domains 
    JOIN records ON domains.id = records.domain_id WHERE records.type = 'SOA' AND domains.name = specialSubDomain;
*/
 

/* Now Do the SRV records, based on what remoteBase is */ 

IF NEW.node_remotebase = 1 THEN
  INSERT INTO records(domain_id, name, type, content, ttl, prio) 
    SELECT proc_domain_id, CONCAT('_iax._udp.', NEW.name, '.', specialSubDomain), 'SRV', 
      CONCAT(srvWeight, ' ', procPort, ' ', NEW.name, '.RemoteBase.', specialSubDomain), proc_ttl, proc_prio 
    ON DUPLICATE KEY UPDATE content = CONCAT(srvWeight, ' ', procPort, ' ', NEW.name, '.RemoteBase.', specialSubDomain);
ELSEIF NEW.node_remotebase = 0 THEN
  INSERT INTO records(domain_id, name, type, content, ttl, prio) 
    SELECT proc_domain_id, CONCAT('_iax._udp.', NEW.name, '.', specialSubDomain), 'SRV', 
      CONCAT(srvWeight, ' ', procPort, ' ', NEW.name, '.', specialSubDomain), proc_ttl, proc_prio 
     ON DUPLICATE KEY UPDATE content = CONCAT(srvWeight, ' ', procPort, ' ', NEW.name, '.', specialSubDomain);
END IF;

/* now the A records 
 There are 4 options here for A records based on remotebase and proxyIP
 we need to clean up the old A records  if remote base is changing 
*/

  IF NEW.node_remotebase != OLD.node_remotebase THEN
    DELETE FROM records 
      WHERE NAME = CONCAT(NEW.name, '.', specialSubDomain) OR NAME = CONCAT(NEW.name, '.RemoteBase.', specialSubDomain) 
      AND ttl = proc_ttl AND TYPE = 'A';
    END IF; 

/* first we do if node remote base is 0 */ 
IF NEW.node_remotebase = 0 THEN
  IF (procProxy_IP IS NULL OR procProxy_IP = ' ') THEN
   INSERT INTO records(domain_id, name, type, content, ttl, prio) 
     SELECT proc_domain_id, CONCAT(NEW.name, '.', specialSubDomain), 'A', NEW.ipaddr, proc_ttl, proc_prio  
     ON DUPLICATE KEY UPDATE content = NEW.ipaddr;
  ELSEIF (procProxy_IP IS NOT NULL AND procProxy_IP !='') THEN
   INSERT INTO records(domain_id, name, type, content, ttl, prio) 
     SELECT proc_domain_id, CONCAT(NEW.name, '.', specialSubDomain), 'A', NEW.ipaddr, proc_ttl, proc_prio  
     ON DUPLICATE KEY UPDATE content = procProxy_IP;
  END IF;
/* Now we do if node remote base is 1 */
ELSEIF NEW.node_remotebase = 1 THEN
  IF (procProxy_IP IS NULL OR procProxy_IP = ' ') THEN
   INSERT INTO records(domain_id, name, type, content, ttl, prio) 
     SELECT proc_domain_id, CONCAT(NEW.name, '.RemoteBase.', specialSubDomain), 'A', NEW.ipaddr, proc_ttl, proc_prio  
     ON DUPLICATE KEY UPDATE content = NEW.ipaddr;
  ELSEIF (procProxy_IP IS NOT NULL AND procProxy_IP !='') THEN
   INSERT INTO records(domain_id, name, type, content, ttl, prio) 
     SELECT proc_domain_id, CONCAT(NEW.name, '.RemoteBase', specialSubDomain), 'A', NEW.ipaddr, proc_ttl, proc_prio  
     ON DUPLICATE KEY UPDATE content = procProxy_IP;
  END IF;
END IF;

/* 
  Time to build TXT records 
  TXT records only exist under *.nodes, the remotebase doesn't have the records 
  NOTE: regseconds must be NULL or 0, if it's ' ' it's not going to work
  update user_Nodes set regseconds = '0'  where regseconds = ' ';
  */
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT  proc_domain_id, 
    CONCAT(NEW.name, '.', specialSubDomain), 
   'TXT', 
    CONCAT('"NN=', NEW.name, '"' ,' ', 
           '"RT=', from_unixtime(IFNULL(NEW.regseconds,'0')),'"', ' ',
           '"RB=', IFNULL(NEW.node_remotebase,'0'), '"', ' ', 
           '"IP=', IFNULL(NEW.ipaddr,'0'), '"', ' ', 
           '"PIP=', IFNULL(procProxy_IP,'0'),'"', ' ', 
           '"PT=', IFNULL(procPort,'0'), '"',' ', 
           '"RH=', IFNULL(NEW.reghostname,'0'), '"'), 
    proc_ttl, 
    proc_prio 
    ON DUPLICATE KEY UPDATE content = CONCAT('"NN=', NEW.name, '"' ,' ', 
           '"RT=', from_unixtime(IFNULL(NEW.regseconds,'0')),'"', ' ',
           '"RB=', IFNULL(NEW.node_remotebase,'0'), '"', ' ', 
           '"IP=', IFNULL(NEW.ipaddr,'0'), '"', ' ', 
           '"PIP=', IFNULL(procProxy_IP,'0'),'"', ' ', 
           '"PT=', IFNULL(procPort,'0'), '"',' ', 
           '"RH=', IFNULL(NEW.reghostname,'0'), '"');
END ; //

DELIMITER ;
COMMIT WORK; 