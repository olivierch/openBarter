drop schema if exists ob cascade;
drop extension if exists flow cascade;
DROP TYPE IF EXISTS ob_ystock cascade;
DROP TYPE IF EXISTS ob_ydraft cascade;
DROP TYPE IF EXISTS ob_yret_stats cascade;

create schema ob;
set search_path = ob;
