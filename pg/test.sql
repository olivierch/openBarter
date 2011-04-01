----------------------------------------------------------------------------------------------------------------
-- ob_fuser_created
----------------------------------------------------------------------------------------------------------------
-- PRIVATE
/* trigger on pg_authid
	when a user is inserted
*/
----------------------------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS ob_fuser_created() cascade;
CREATE FUNCTION ob_fuser_created() RETURNS trigger AS $$
BEGIN
	INSERT INTO ob_towner (name) VALUES (OLD.rolname);
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trig_befb_pg_authid BEFORE INSERT ON pg_authid  FOR EACH ROW 
  EXECUTE PROCEDURE ob_fuser_created();
