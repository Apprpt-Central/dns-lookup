DELIMITER //

DROP TEMPORARY TABLE IF EXISTS records;
CREATE TEMPORARY TABLE frecords (
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

/*  Declare shit here before anything else */
  
   SET @proc_prio = '11' ;
   SET @disabled = '0' ;
  /*
  set this specialSubDomain to the subdomain used for the nodes database
  */
   SET @specialSubDomain = 'nodes.allstarlink.org';
   SET @disabled = '0' ;
   SET @srvWeight = '10' ;
  /*
  proc_ttl here is used as a special key.  We first delete anything in the db with this ttl
  if you want to make static records in the DB they must use a different TTL than 30
  */
   SET @proc_ttl = '30' ;  
  /* 
  pull the id and auth fields from the domains and records 
  */ 
   SELECT `id` INTO @proc_domain_id FROM domains WHERE `name` = @specialSubDomain;
   SELECT `auth` INTO @proc_auth FROM records WHERE `type` = 'SOA' AND `domain_id` = @proc_domain_id;
/* 
  clean up the table for anything with the TTL and domain ID matching
*/
  DELETE FROM records WHERE  domain_id = @proc_domain_id AND ttl = @proc_ttl;

  /* 
    DO the SRV RECORDS
  If not a remote base
  */ 
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT @proc_domain_id, CONCAT('_iax._udp.', name, '.', @specialSubDomain), 'SRV', 
    CONCAT(@srvWeight, ' ', udpport, ' ', name, '.', @specialSubDomain), @proc_ttl, @proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND name !=' ' AND node_remotebase =0 ;
 /* 
  If it is a remote base
  */ 
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT @proc_domain_id, CONCAT('_iax._udp.', name, '.', @specialSubDomain), 'SRV', 
    CONCAT(@srvWeight, ' ', udpport, ' ', name, '.RemoteBase.', @specialSubDomain), @proc_ttl, @proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase =1 ;

/*
  Now we do the A records
  We have to do 4, one for proxy IP one for remotebase
  First do the if not a proxy or remotebase
*/
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT @proc_domain_id, CONCAT(name, '.', @specialSubDomain), 'A', ipaddr, @proc_ttl, @proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 0 AND (proxy_ip IS NULL OR proxy_ip = ' ');

/*
   Now if a proxy= 1 but not remotebase
*/
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT @proc_domain_id, CONCAT(name, '.', @specialSubDomain), 'A', proxy_ip, @proc_ttl, @proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 0 AND (proxy_ip IS NOT NULL AND proxy_ip !='');

/*
  Remotebase = 1
  Proxy = 0
 */
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT @proc_domain_id, CONCAT(name, '.RemoteBase.', @specialSubDomain), 'A', ipaddr, @proc_ttl, @proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 1 AND (proxy_ip IS NULL OR proxy_ip = ' ');

/*
  Remotebase = 1
  Proxy = 1
*/
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT @proc_domain_id, CONCAT(name, '.RemoteBase.', @specialSubDomain), 'A', proxy_ip, @proc_ttl, @proc_prio  FROM 
    user_Nodes JOIN user_Servers USING (Config_ID) WHERE ipaddr IS NOT NULL AND Status = 'Active' AND node_remotebase = 1 AND (proxy_ip IS NOT NULL AND proxy_ip !='');

/* 
  now we do the TXT records
  TXT records only exist under *.nodes, the remotebase doesn't have the records 

  */
INSERT INTO records(domain_id, name, type, content, ttl, prio) 
  SELECT  @proc_domain_id, 
    CONCAT(name, '.', @specialSubDomain), 
   'TXT', 
    CONCAT('"NN=', name, '"' ,' ', 
           '"RT=', from_unixtime(IFNULL(regseconds,'0')),'"', ' ',
           '"RB=', IFNULL(node_remotebase,'0'), '"', ' ', 
           '"IP=', IFNULL(ipaddr,'0'), '"', ' ', 
           '"PIP=', IFNULL(proxy_ip,'0'),'"', ' ', 
           '"PT=', IFNULL(udpport,'0'), '"',' ', 
           '"RH=', IFNULL(reghostname,'0'), '"'), 
    @proc_ttl, 
    @proc_prio 
    FROM 
  user_Nodes JOIN user_Servers USING (Config_ID) WHERE Status = 'Active' ;


SELECT * FROM records; 