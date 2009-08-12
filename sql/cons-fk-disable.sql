--
--
-- cons-fk.sql
--    user constraints - disable foreign keys
--
-- Usage:
--     SQL> @cons-fk-disable
--
--    Marcus Vinicius Ferreira                  ferreira.mv[ at ] gmail.com
--    2009-08
--


SET PAGESIZE 200
SET FEEDBACK OFF
SET VERIFY   OFF

SELECT 'alter table '        || RPAD( cons.owner ||'.'|| cons.table_name, 50, ' ' )
    || ' disable constraint '|| RPAD(cons.constraint_name, 31, ' ')
    || ';' cmd
  FROM user_constraints   cons
 WHERE cons.constraint_type = 'R'
   AND status = 'ENABLED'
 ORDER BY table_name,constraint_name,owner
/

SET FEEDBACK ON
SET VERIFY   ON


