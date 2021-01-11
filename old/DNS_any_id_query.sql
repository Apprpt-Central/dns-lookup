START TRANSACTION;
DELIMITER //
CREATE OR REPLACE procedure DNS_any_id_query (  
  IN IN_name VARCHAR(64),
  IN IN_id int(11) 
  )
BEGIN
   /* 
    Replacement sproc for the PowerDNS gmysql-any-id-query for AllStarLink
    Copyright (C) 2019 Bryan Fields
    bryan@bryanfields.net
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

  now the replacement for # gmysql-any-id-query 
  SELECT content,ttl,prio,type,domain_id,disabled,name,auth FROM records 
  WHERE disabled=0 and name=? and domain_id=?
--------------------------- Revision History ----------------------------------
  2019-05-02     bfields     Inital working prototype
  2019-05-28     bfields     Added reg host to TXT record
  
*/
 

 /* 
  Declare stuff here before anything else
 */
  DECLARE remoteBase VARCHAR(4);
  DECLARE udp VARCHAR(6);
  DECLARE finished INTEGER DEFAULT 0;
  DECLARE srvWeight INT;
  DECLARE nodeNumber VARCHAR(64);
  DECLARE proc_domain_id INT DEFAULT NULL;
  DECLARE QueryContent TEXT; 
  DECLARE proc_ttl INT DEFAULT NULL;
  DECLARE proc_prio INT DEFAULT NULL;
  DECLARE disabled TINYINT(1);
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

DECLARE txtCursor CURSOR FOR
  SELECT regseconds, node_remotebase, udpport, proxy_ip, ipaddr, reghostname FROM 
  user_Nodes JOIN user_Servers USING (Config_ID) WHERE `name` = nodeNumber ;  

 DECLARE srvCursor CURSOR FOR 
  SELECT node_remotebase, udpport FROM user_Nodes JOIN user_Servers USING (Config_ID) WHERE name = nodeNumber AND ipaddr IS NOT NULL; 
 /* the A selection */
 DECLARE aCursor CURSOR FOR
  SELECT proxy_ip, ipaddr FROM user_Nodes JOIN user_Servers USING (Config_ID) WHERE `name` = nodeNumber ;  

DECLARE CONTINUE HANDLER 
  FOR NOT FOUND SET finished = 1;


/* Clean up the input to be all lower case for the query */
   SET IN_name = LOWER(IN_name);
  /* SET IN_type = UPPER(IN_type); */
   SET srvWeight = '10' ; 
   SET proc_prio = '10' ;  
   SET disabled = '0' ;
   SET specialSubDomain = 'nodes.allstarlink.org';
   SET disabled = '0' ;
   SET srvWeight = '10' ;
  /* set the proc_domain_id var from IN_id */
   SET proc_domain_id = IN_id ;

/* pull the auth and ttl setting from the SOA record */ 
   SELECT `ttl` INTO proc_ttl FROM records WHERE `type` = 'SOA' AND `domain_id` = proc_domain_id; 

   SELECT `auth` INTO proc_auth FROM records WHERE `type` = 'SOA' AND `domain_id` = proc_domain_id;

  DROP TABLE IF EXISTS tempRecords;

CREATE TEMPORARY TABLE tempRecords (
  temp_domain_id INT DEFAULT NULL,
  temp_name   VARCHAR(255) DEFAULT NULL,
  type        VARCHAR(10) DEFAULT NULL,
  content     TEXT DEFAULT NULL,
  proc_ttl         INT DEFAULT NULL,
  prio        INT DEFAULT NULL,
  change_date INT DEFAULT NULL,
  disabled    TINYINT(1) DEFAULT 0,
  ordername   VARCHAR(255) BINARY DEFAULT NULL,
  proc_auth        TINYINT(1) DEFAULT 1
  );

/* we need to select every thing now */
/* ok now we need to handle the special records, SRV, A and TXT */
/* handle the SRV record */
/* IF IN_type = 'SRV' THEN */
  IF SUBSTRING_INDEX(IN_name,'.',-3) = specialSubDomain AND  SUBSTRING_INDEX(IN_name,'.',2) = '_iax._udp' THEN
      SET nodeNumber = SUBSTRING_INDEX(SUBSTRING_INDEX(IN_name, (CONCAT('.', specialSubDomain)), 1),'_iax._udp.',-1);
  ELSEIF SUBSTRING_INDEX(IN_name,'.',-4) = (CONCAT('remotebase.', specialSubDomain))  THEN
      SET nodeNumber = SUBSTRING_INDEX(IN_name,(CONCAT('.remotebase.', specialSubDomain)), 1);
  ELSEIF SUBSTRING_INDEX(IN_name,'.',-3) = specialSubDomain THEN
      SET nodeNumber =  SUBSTRING_INDEX(IN_name,(CONCAT('.', specialSubDomain)) , 1);
  END IF;  

/* Now lets process the records from the srvCursor query */
      OPEN srvCursor;
      is_srv_loop: LOOP
      FETCH srvCursor INTO remoteBase, udp ;

       IF finished = 1 THEN 
  
        LEAVE is_srv_loop;
       END IF;
       IF remoteBase = '1' THEN
        INSERT INTO tempRecords(content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth) 
          SELECT (CONCAT(srvWeight, ' ', udp, ' ', nodeNumber,'.RemoteBase.', specialSubDomain)), proc_ttl, proc_prio,
            'SRV', proc_domain_id, disabled, IN_name, proc_auth;
        ELSEIF remoteBase = '0' THEN
         INSERT INTO tempRecords(content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth) 
          SELECT (CONCAT(srvWeight, ' ', udp, ' ', nodeNumber, '.', specialSubDomain)), proc_ttl, proc_prio,
          'SRV', proc_domain_id, disabled, IN_name, proc_auth;
       END IF;
      END LOOP is_srv_loop;
      CLOSE srvCursor;
  /* now lets set finished to 0 again so the next loop works */
  SET finished = '0';

 
/* Now process the A records */
/* Process the records from the aCursor query */
      OPEN aCursor;
      is_A_loop: LOOP
      FETCH aCursor INTO aProxy_IP, aIPaddr ;
       IF finished = 1 THEN 
        LEAVE is_A_loop;
       END IF;

/* ok not if proxy IP is null, then return the ipaddr */
       IF aProxy_IP IS null THEN
        INSERT INTO tempRecords(content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth) 
          SELECT aIPaddr, proc_ttl, proc_prio, 'A', proc_domain_id, disabled, IN_name, proc_auth;
        ELSEIF aProxy_IP IS NOT NULL THEN
         INSERT INTO tempRecords(content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth) 
          SELECT aIPaddr, proc_ttl, proc_prio, 'A', proc_domain_id, disabled, IN_name, proc_auth;
       END IF;
      END LOOP is_A_loop;
      CLOSE aCursor;
/* now lets set finished to 0 again so the next loop works */
  SET finished = '0';

 
/* Now Handle the TXT record query */
/* Now lets process the records from the srvCursor query */
      OPEN txtCursor;
      is_TXT_loop: LOOP
      FETCH txtCursor INTO txtRegSeconds, txtRemoteBase, txtPort, txtProxy_IP, txtIPaddr, txtRegHostName ;

       IF finished = 1 THEN 
  
        LEAVE is_TXT_loop;
       END IF;
/* put each record in the temp table */
       INSERT INTO tempRecords(content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth) 
          SELECT CONCAT('"NN=', nodeNumber, '"' ,' ', '"RT=', from_unixtime(IFNULL(txtRegSeconds,0)),'"', ' ', '"RB=', 
          IFNULL(txtRemoteBase,0), '"', ' ', '"IP=', IFNULL(txtIPaddr,''), '"', ' ', '"PIP=', IFNULL(txtProxy_IP,''),'"', ' ', 
          '"PT=', IFNULL(txtPort,''), '"',' ', '"RH=', txtRegHostName, '"'), proc_ttl, proc_prio, 'TXT', proc_domain_id, disabled, IN_name, proc_auth;
      END LOOP is_TXT_loop;
      CLOSE txtCursor;
  /* now lets set finished to 0 again so the next loop works */
  SET finished = '0';

/* END IF; */



/* ok, just do a normal lookup */
  INSERT INTO tempRecords(content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth) 
    SELECT content,ttl,prio,type,domain_id,disabled,name,auth FROM records WHERE disabled=0 
     AND name = IN_name AND domain_id = proc_domain_id ;
/* END IF; */
SELECT content,proc_ttl,prio,type,temp_domain_id,disabled,temp_name,proc_auth FROM tempRecords;
DROP TABLE tempRecords;
END; //
DELIMITER ;
COMMIT;
