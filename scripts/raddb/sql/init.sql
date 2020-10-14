CREATE TABLE IF NOT EXISTS radacct (
  RadAcctId		bigserial PRIMARY KEY,
  AcctSessionId		text NOT NULL,
  AcctUniqueId		text NOT NULL UNIQUE,
  UserName		text,
  Realm			text,
  NASIPAddress		inet NOT NULL,
  NASPortId		text,
  NASPortType		text,
  AcctStartTime		timestamp with time zone,
  AcctUpdateTime		timestamp with time zone,
  AcctStopTime		timestamp with time zone,
  AcctInterval		bigint,
  AcctSessionTime		bigint,
  AcctAuthentic		text,
  ConnectInfo_start	text,
  ConnectInfo_stop	text,
  AcctInputOctets		bigint,
  AcctOutputOctets	bigint,
  CalledStationId		text,
  CallingStationId	text,
  AcctTerminateCause	text,
  ServiceType		text,
  FramedProtocol		text,
  FramedIPAddress		inet,
  FramedIPv6Address	inet,
  FramedIPv6Prefix	inet,
  FramedInterfaceId	text,
  DelegatedIPv6Prefix	inet
);
CREATE UNIQUE INDEX radacct_whoson on radacct (AcctStartTime, nasipaddress);
CREATE INDEX radacct_active_session_idx ON radacct (AcctUniqueId) WHERE AcctStopTime IS NULL;
CREATE INDEX radacct_session_idx ON radacct (AcctUniqueId);
CREATE INDEX radacct_bulk_close ON radacct (NASIPAddress, AcctStartTime) WHERE AcctStopTime IS NULL;
CREATE INDEX radacct_start_user_idx ON radacct (AcctStartTime, UserName);
CREATE INDEX radacct_stop_user_idx ON radacct (acctStopTime, UserName);


CREATE TABLE IF NOT EXISTS radcheck (
  id			serial PRIMARY KEY,
  UserName		text NOT NULL DEFAULT '',
  Attribute		text NOT NULL DEFAULT '',
  op			VARCHAR(2) NOT NULL DEFAULT '==',
  Value			text NOT NULL DEFAULT ''
);
create index radcheck_UserName on radcheck (UserName,Attribute);
insert into radcheck (id, UserName, op, Attribute, Value) VALUES ('1', 'hello', ':=', 'Cleartext-Password', 'world');

CREATE TABLE IF NOT EXISTS radgroupcheck (
  id			serial PRIMARY KEY,
  GroupName		text NOT NULL DEFAULT '',
  Attribute		text NOT NULL DEFAULT '',
  op			VARCHAR(2) NOT NULL DEFAULT '==',
  Value			text NOT NULL DEFAULT ''
);
create index radgroupcheck_GroupName on radgroupcheck (GroupName,Attribute);

CREATE TABLE IF NOT EXISTS radgroupreply (
  id			serial PRIMARY KEY,
  GroupName		text NOT NULL DEFAULT '',
  Attribute		text NOT NULL DEFAULT '',
  op			VARCHAR(2) NOT NULL DEFAULT '=',
  Value			text NOT NULL DEFAULT ''
);
create index radgroupreply_GroupName on radgroupreply (GroupName,Attribute);

CREATE TABLE IF NOT EXISTS radreply (
  id			serial PRIMARY KEY,
  UserName		text NOT NULL DEFAULT '',
  Attribute		text NOT NULL DEFAULT '',
  op			VARCHAR(2) NOT NULL DEFAULT '=',
  Value			text NOT NULL DEFAULT ''
);
create index radreply_UserName on radreply (UserName,Attribute);
insert into radreply (id, UserName, op, Attribute, Value) VALUES ('1', 'hello', ':=', 'Reply-Message', 'Hello World!');

CREATE TABLE IF NOT EXISTS radusergroup (
  id			serial PRIMARY KEY,
  UserName		text NOT NULL DEFAULT '',
  GroupName		text NOT NULL DEFAULT '',
  priority		integer NOT NULL DEFAULT 0
);
create index radusergroup_UserName on radusergroup (UserName);

CREATE TABLE IF NOT EXISTS radpostauth (
  id			bigserial PRIMARY KEY,
  username		text NOT NULL,
  pass			text,
  reply			text,
  CalledStationId		text,
  CallingStationId	text,
  authdate		timestamp with time zone NOT NULL default now()
);

CREATE TABLE IF NOT EXISTS nas (
  id			serial PRIMARY KEY,
  nasname			text NOT NULL,
  shortname		text NOT NULL,
  type			text NOT NULL DEFAULT 'other',
  ports			integer,
  secret			text NOT NULL,
  server			text,
  community		text,
  description		text
);
create index nas_nasname on nas (nasname);


CREATE TABLE data_usage_by_period (
    username text,
    period_start timestamp with time zone,
    period_end timestamp with time zone,
    acctinputoctets bigint,
    acctoutputoctets bigint
);
ALTER TABLE data_usage_by_period ADD CONSTRAINT data_usage_by_period_pkey PRIMARY KEY (username, period_start);
CREATE INDEX data_usage_by_period_pkey_period_end ON data_usage_by_period(period_end);


CREATE TABLE radippool (
  id			BIGSERIAL PRIMARY KEY,
  pool_name		varchar(64) NOT NULL,
  FramedIPAddress		INET NOT NULL,
  NASIPAddress		VARCHAR(16) NOT NULL default '',
  pool_key		VARCHAR(64) NOT NULL default '',
  CalledStationId		VARCHAR(64) NOT NULL default '',
  CallingStationId	text NOT NULL default ''::text,
  expiry_time		TIMESTAMP(0) without time zone NOT NULL default NOW(),
  username		text DEFAULT ''::text
);
CREATE INDEX radippool_poolname_expire ON radippool USING btree (pool_name, expiry_time);
CREATE INDEX radippool_framedipaddress ON radippool USING btree (framedipaddress);
CREATE INDEX radippool_nasip_poolkey_ipaddress ON radippool USING btree (nasipaddress, pool_key, framedipaddress);
CREATE INDEX radippool_poolname_username_callingstationid ON radippool(pool_name,username,callingstationid);

CREATE TYPE dhcp_status AS ENUM ('dynamic', 'static', 'declined', 'disabled');
CREATE TABLE dhcpippool (
  id			BIGSERIAL PRIMARY KEY,
  pool_name		varchar(64) NOT NULL,
  FramedIPAddress		INET NOT NULL,
  pool_key		VARCHAR(64) NOT NULL default '0',
  gateway			VARCHAR(16) NOT NULL default '',
  expiry_time		TIMESTAMP(0) without time zone NOT NULL default NOW(),
  status			dhcp_status DEFAULT 'dynamic',
  counter			INT NOT NULL default 0
);
CREATE INDEX dhcpippool_poolname_expire ON dhcpippool USING btree (pool_name, expiry_time);
CREATE INDEX dhcpippool_framedipaddress ON dhcpippool USING btree (framedipaddress);
CREATE INDEX dhcpippool_poolname_poolkey_ipaddress ON dhcpippool USING btree (pool_name, pool_key, framedipaddress);





CREATE OR REPLACE FUNCTION fr_new_data_usage_period ()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_start timestamp;
DECLARE v_end timestamp;
BEGIN

    SELECT COALESCE(MAX(period_end) + INTERVAL '1 SECOND', TO_TIMESTAMP(0)) INTO v_start FROM data_usage_by_period;
    SELECT DATE_TRUNC('second',CURRENT_TIMESTAMP) INTO v_end;

    INSERT INTO data_usage_by_period (username, period_start, period_end, acctinputoctets, acctoutputoctets)
    SELECT *
    FROM (
        SELECT
            username,
            v_start,
            v_end,
            SUM(acctinputoctets) AS acctinputoctets,
            SUM(acctoutputoctets) AS acctoutputoctets
        FROM
            radacct
        WHERE
            acctstoptime > v_start OR
            acctstoptime IS NULL
        GROUP BY
            username
    ) AS s
    ON CONFLICT ON CONSTRAINT data_usage_by_period_pkey
    DO UPDATE
        SET
            acctinputoctets = data_usage_by_period.acctinputoctets + EXCLUDED.acctinputoctets,
            acctoutputoctets = data_usage_by_period.acctoutputoctets + EXCLUDED.acctoutputoctets,
            period_end = v_end;

    INSERT INTO data_usage_by_period (username, period_start, period_end, acctinputoctets, acctoutputoctets)
    SELECT *
    FROM (
        SELECT
            username,
            v_end + INTERVAL '1 SECOND',
            NULL::timestamp,
            0 - SUM(acctinputoctets),
            0 - SUM(acctoutputoctets)
        FROM
            radacct
        WHERE
            acctstoptime IS NULL
        GROUP BY
            username
    ) AS s;

END
$$;




CREATE OR REPLACE FUNCTION fr_allocate_previous_or_new_framedipaddress (
  v_pool_name VARCHAR(64),
  v_username VARCHAR(64),
  v_callingstationid VARCHAR(64),
  v_nasipaddress VARCHAR(16),
  v_pool_key VARCHAR(64),
  v_lease_duration INT
)
RETURNS inet
LANGUAGE plpgsql
AS $$
DECLARE
  r_address inet;
BEGIN

  SELECT framedipaddress INTO r_address
  FROM radippool
  WHERE pool_name = v_pool_name
    AND expiry_time > NOW()
    AND username = v_username
    AND callingstationid = v_callingstationid
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF r_address IS NULL THEN
    SELECT framedipaddress INTO r_address
    FROM radippool
    WHERE pool_name = v_pool_name
    AND expiry_time < NOW()
    ORDER BY
        expiry_time
    LIMIT 1
    FOR UPDATE SKIP LOCKED;
  END IF;

  IF r_address IS NULL THEN
    RETURN r_address;
  END IF;

  UPDATE radippool
  SET
    nasipaddress = v_nasipaddress,
    pool_key = v_pool_key,
    callingstationid = v_callingstationid,
    username = v_username,
    expiry_time = NOW() + v_lease_duration * interval '1 sec'
  WHERE framedipaddress = r_address;

  RETURN r_address;

END
$$;




CREATE OR REPLACE FUNCTION fr_dhcp_allocate_previous_or_new_framedipaddress (
  v_pool_name VARCHAR(64),
  v_gateway VARCHAR(16),
  v_pool_key VARCHAR(64),
  v_lease_duration INT,
  v_requested_address INET
)
RETURNS inet
LANGUAGE plpgsql
AS $$
DECLARE
  r_address INET;
BEGIN

  WITH ips AS (
    SELECT framedipaddress FROM dhcpippool
    WHERE pool_name = v_pool_name
      AND pool_key = v_pool_key
      AND expiry_time > NOW()
      AND status IN ('dynamic', 'static')
    LIMIT 1 FOR UPDATE SKIP LOCKED )
  UPDATE dhcpippool
  SET expiry_time = NOW() + v_lease_duration * interval '1 sec'
  FROM ips WHERE dhcpippool.framedipaddress = ips.framedipaddress
  RETURNING dhcpippool.framedipaddress INTO r_address;

  IF r_address IS NULL AND v_requested_address != '0.0.0.0' THEN
    WITH ips AS (
      SELECT framedipaddress FROM dhcpippool
      WHERE pool_name = v_pool_name
        AND framedipaddress = v_requested_address
        AND status = 'dynamic'
        AND ( pool_key = v_pool_key OR expiry_time < NOW() )
      LIMIT 1 FOR UPDATE SKIP LOCKED )
    UPDATE dhcpippool
    SET pool_key = v_pool_key,
      expiry_time = NOW() + v_lease_duration * interval '1 sec',
      gateway = v_gateway
    FROM ips WHERE dhcpippool.framedipaddress = ips.framedipaddress
    RETURNING dhcpippool.framedipaddress INTO r_address;
  END IF;

  IF r_address IS NULL THEN
    WITH ips AS (
      SELECT framedipaddress FROM dhcpippool
      WHERE pool_name = v_pool_name
        AND expiry_time < NOW()
        AND status = 'dynamic'
      ORDER BY expiry_time
      LIMIT 1 FOR UPDATE SKIP LOCKED )
    UPDATE dhcpippool
    SET pool_key = v_pool_key,
      expiry_time = NOW() + v_lease_duration * interval '1 sec',
      gateway = v_gateway
    FROM ips WHERE dhcpippool.framedipaddress = ips.framedipaddress
    RETURNING dhcpippool.framedipaddress INTO r_address;
  END IF;

  RETURN r_address;

END
$$;


CREATE OR REPLACE FUNCTION "greater"(integer, integer) RETURNS integer AS '
    DECLARE
        res INTEGER;
        one INTEGER := 0;
        two INTEGER := 0;
    BEGIN
        one = $1;
        two = $2;
        IF one IS NULL THEN
            one = 0;
        END IF;
        IF two IS NULL THEN
            two = 0;
        END IF;
        IF one > two THEN
            res := one;
        ELSE
            res := two;
        END IF;
        RETURN res;
    END;
' LANGUAGE 'plpgsql';