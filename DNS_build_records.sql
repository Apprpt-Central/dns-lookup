START TRANSACTION;
DELIMITER //
CREATE OR REPLACE procedure DNS_build_records () 
BEGIN
  /* 
    This will build SRV,TXT, and A records into the 'records' table for power DNS
    for AllStarLink
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
  2019-06-08      bfields     Inital prototype
  2019-06-09      bfields     Added some handeling for stuff = ' ' in the DB :smh:
   
*/

/*  Declare stuff here before anything else */


  DECLARE remoteBase VARCHAR(4);
  DECLARE udp VARCHAR(6);
  DECLARE finished INTEGER DEFAULT 0;
  DECLARE srvWeight int DEFAULT 10;
  DECLARE nodeNumber VARCHAR(64);
  DECLARE proc_domain_id INT DEFAULT NULL;
  DECLARE QueryContent TEXT; 
  DECLARE proc_ttl INT DEFAULT NULL;
  DECLARE proc_prio INT DEFAULT 11;
  DECLARE disabled TINYINT(1) DEFAULT 0;
  DECLARE proc_auth TINYINT(1);
  DECLARE specialSubDomain varchar(64);
  DECLARE aProxy_IP varchar(20);
  DECLARE aIPaddr varchar(20);
  DECLARE txtRegSeconds varchar(20);
  DECLARE txtRemoteBase varchar(2);
  DECLARE txtPort varchar (6);
  DECLARE txtProxy_IP varchar(20);
  DECLARE txtIPaddr varchar(20);
  DECLARE txtRegHostName varchar(32);
  DECLARE errno INT;
  DECLARE err_loc INT; 

  DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
      GET CURRENT DIAGNOSTICS CONDITION 1 errno = MYSQL_ERRNO;
      SELECT errno AS MYSQL_ERROR, err_loc AS location ;
      SELECT 'holyfuckingshit'; 
      ROLLBACK; 
    END;

START TRANSACTION WITH CONSISTENT SNAPSHOT;
    /* 
  This is not needed as it's defined by default ^ there
   SET proc_prio = '11' ;
   SET disabled = '0' ;
   SET disabled = '0' ;
   SET srvWeight = '10' ;
  set this specialSubDomain to the subdomain used for the nodes database
  */
   SET specialSubDomain = 'nodes.allstarlink.org';

  /*
  proc_ttl here is used as a special key.  We first delete anything in the db with this ttl
  if you want to make static records in the DB they must use a different TTL than 30
  */
   SET proc_ttl = '30' ;  
  /* 
  pull the id and auth fields from the domains and records 
  */
SET err_loc = '1' ;
   
   SELECT `id` INTO proc_domain_id FROM domains WHERE `name` = specialSubDomain;
   SELECT `auth` INTO proc_auth FROM records WHERE `type` = 'SOA' AND `domain_id` = proc_domain_id;
/* 
  clean up the table for anything with the TTL and domain ID matching
*/
  DELETE FROM records WHERE  domain_id = proc_domain_id AND ttl = proc_ttl;
/*
    NOTE: regseconds/ipaddr must be NULL or 0, if it's ' ' it's not going to work
  update user_Nodes set regseconds = '0'  where regseconds = ' ';
  update user_Nodes set ipaddr='0.0.0.0' where ipaddr = ' ';
*/
  /* 
  If not a remote base
  */ 
SET err_loc = '2';
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT proc_domain_id, CONCAT('_iax._udp.', name, '.', specialSubDomain), 'SRV', 
    CONCAT(srvWeight, ' ', udpport, ' ', name, '.', specialSubDomain), proc_ttl, proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase =0 ;
 /* 
  If it is a remote base
  */ 
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT proc_domain_id, CONCAT('_iax._udp.', name, '.', specialSubDomain), 'SRV', 
    CONCAT(srvWeight, ' ', udpport, ' ', name, '.RemoteBase.', specialSubDomain), proc_ttl, proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase =1 ;

  SET err_loc = '10';
/*
  Now we do the A records
  We have to do 4, one for proxy IP one for remotebase
  First do the if not a proxy or remotebase
*/
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT proc_domain_id, CONCAT(name, '.', specialSubDomain), 'A', ipaddr, proc_ttl, proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 0 AND(proxy_ip IS NULL OR proxy_ip = ' ');
/*
   Now if a proxy but not remotebase
*/
 SET err_loc = '11';
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT proc_domain_id, CONCAT(name, '.', specialSubDomain), 'A', proxy_ip, proc_ttl, proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 0 AND (proxy_ip IS NOT NULL AND proxy_ip !='');
/*
  Remotebase = 1
  Proxy = 0
 */
 SET err_loc = '12';
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT proc_domain_id, CONCAT(name, '.RemoteBase.', specialSubDomain), 'A', ipaddr, proc_ttl, proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 1 AND (proxy_ip IS NULL OR proxy_ip = ' ');
/*
  Remotebase = 1
  Proxy = 1
*/
 SET err_loc = '13';
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT proc_domain_id, CONCAT(name, '.RemoteBase.', specialSubDomain), 'A', proxy_ip, proc_ttl, proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 1 AND (proxy_ip IS NOT NULL AND proxy_ip !='');

  SET err_loc = '20';
/* 
  now we do the TXT records
  TXT records only exist under *.nodes, the remotebase doesn't have the records 
  NOTE: regseconds must be NULL or 0, if it's ' ' it's not going to work
  update user_Nodes set regseconds = '0'  where regseconds = ' ';
  */
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT  proc_domain_id, 
    CONCAT(name, '.', specialSubDomain), 
   'TXT', 
    CONCAT('"NN=', name, '"' ,' ', 
           '"RT=', from_unixtime(IFNULL(regseconds,'0')),'"', ' ',
           '"RB=', IFNULL(node_remotebase,'0'), '"', ' ', 
           '"IP=', IFNULL(ipaddr,'0'), '"', ' ', 
           '"PIP=', IFNULL(proxy_ip,'0'),'"', ' ', 
           '"PT=', IFNULL(udpport,'0'), '"',' ', 
           '"RH=', IFNULL(reghostname,'0'), '"'), 
    proc_ttl, 
    proc_prio 
    FROM 
  user_Nodes JOIN user_Servers USING (Config_ID) WHERE Status = 'Active';
SET err_loc = '30';

COMMIT WORK ;
SET err_loc = '40';
END ; //

DELIMITER ;
COMMIT WORK;  
  
