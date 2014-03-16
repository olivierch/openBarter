\set ECHO none
/* roles.sql must be executed previously */

drop schema if exists market cascade;
create schema market;
set search_path to market;


\i sql/roles.sql

GRANT USAGE ON SCHEMA market TO role_com;

\i sql/util.sql
\i sql/tables.sql
\i sql/prims.sql
\i sql/pushpull.sql
\i sql/currencies.sql
\i sql/algo.sql
\i sql/openclose.sql

create view vord as (SELECT 
	(ord).id,
	(ord).oid,
                own,

                
                
                
                
                (ord).qtt_requ,
                (ord).qua_requ,
                CASE WHEN (ord).type=1 THEN 'limit' ELSE 'best' END typ,
                (ord).qtt_prov,
                (ord).qua_prov,
                (ord).qtt,
                
                (ord).own as own_id,
                usr
                -- duration 
        FROM market.torder order by (ord).id asc);

select * from fversion();
\echo model installed.

