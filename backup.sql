--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: prostgles; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA prostgles;


ALTER SCHEMA prostgles OWNER TO postgres;

--
-- Name: SCHEMA prostgles; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA prostgles IS 'Used by prostgles-server to enable data/schema change tracking through subscribe/sync/watchSchema';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: debug(text[]); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.debug(VARIADIC args text[]) RETURNS void
    LANGUAGE plpgsql
    AS $$     
          BEGIN

            --PERFORM pg_notify('debug', concat_ws(' ', args));
            IF
                NOT EXISTS (
                    SELECT 1 
                    FROM information_schema.tables 
                    WHERE  table_schema = 'prostgles'
                    AND    table_name   = 'debug'
                )
            THEN
              CREATE TABLE IF NOT EXISTS prostgles.debug(m TEXT);
            END IF;

            INSERT INTO prostgles.debug(m) VALUES(concat_ws(' ', args));

          END;
        $$;


ALTER FUNCTION prostgles.debug(VARIADIC args text[]) OWNER TO postgres;

--
-- Name: FUNCTION debug(VARIADIC args text[]); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.debug(VARIADIC args text[]) IS 'Used for internal debugging';


--
-- Name: prostgles_trigger_function(); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.prostgles_trigger_function() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$

            DECLARE t_ids TEXT[];
            DECLARE c_ids INTEGER[];  
            DECLARE err_c_ids INTEGER[]; 
            DECLARE unions TEXT := '';          
            DECLARE query TEXT := '';            
            DECLARE v_trigger RECORD;
            DECLARE has_errors BOOLEAN := FALSE;
            
            DECLARE err_text    TEXT;
            DECLARE err_detail  TEXT;
            DECLARE err_hint    TEXT;
                    
            DECLARE view_def_query TEXT := '';   

            DECLARE escaped_table  TEXT;

            BEGIN

                --PERFORM pg_notify('debug', concat_ws(' ', 'TABLE', TG_TABLE_NAME, TG_OP));
            
                escaped_table := concat_ws('.', CASE WHEN TG_TABLE_SCHEMA <> CURRENT_SCHEMA THEN format('%I', TG_TABLE_SCHEMA) END, format('%I', TG_TABLE_NAME));

                SELECT string_agg(
                  format(
                    $c$ 
                      SELECT CASE WHEN EXISTS( 
                        SELECT 1 
                        FROM %s 
                        WHERE %s 
                      ) THEN %s::text END AS t_ids 
                    $c$, 
                    table_name, 
                    condition, 
                    id 
                  ),
                  E' UNION 
 ' 
                ) 
                INTO unions
                FROM prostgles.v_triggers
                WHERE table_name = escaped_table;


                /* unions = 'old_table union new_table' or any one of the tables */
                IF unions IS NOT NULL THEN

                    SELECT  
                      format(
                        E'WITH %I AS (
 %s 
) ', 
                        TG_TABLE_NAME, 
                        concat_ws(
                          E' UNION ALL 
 ',
                          CASE WHEN (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN ' SELECT * FROM old_table ' END,
                          CASE WHEN (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN ' SELECT * FROM new_table ' END 
                        )
                      ) 
                      || 
                      COALESCE((
                        SELECT ', ' || string_agg(format(E' %s AS ( 
 %s 
 ) ', related_view_name, related_view_def), ', ')
                        FROM (
                          SELECT DISTINCT related_view_name, related_view_def 
                          FROM prostgles.v_triggers
                          WHERE table_name = escaped_table
                          AND related_view_name IS NOT NULL
                          AND related_view_def  IS NOT NULL
                        ) t
                      ), '')
                      || 
                      format(
                        $c$
                            SELECT ARRAY_AGG(DISTINCT t.t_ids)
                            FROM ( 
                              %s 
                            ) t
                        $c$, 
                        unions
                      )
                    INTO query; 

                    BEGIN
                      EXECUTE query INTO t_ids;

                      --RAISE NOTICE 'trigger fired ok';

                    EXCEPTION WHEN OTHERS THEN
                      
                      has_errors := TRUE;

                      GET STACKED DIAGNOSTICS 
                        err_text = MESSAGE_TEXT,
                        err_detail = PG_EXCEPTION_DETAIL,
                        err_hint = PG_EXCEPTION_HINT;

                    END;

                    --RAISE NOTICE 'has_errors: % ', has_errors;
                    --RAISE NOTICE 'unions: % , cids: %', unions, c_ids;

                    IF (t_ids IS NOT NULL OR has_errors) THEN

                        FOR v_trigger IN
                            SELECT app_id, string_agg(c_id::text, ',') as cids
                            FROM prostgles.v_triggers
                            WHERE id = ANY(t_ids) 
                            OR has_errors
                            GROUP BY app_id
                        LOOP
                            
                            PERFORM pg_notify( 
                              'prostgles_' || v_trigger.app_id , 
                              LEFT(concat_ws(
                                '|$prstgls$|',

                                'data_has_changed', 
                                COALESCE(escaped_table, 'MISSING'), 
                                COALESCE(TG_OP, 'MISSING'), 
                                CASE WHEN has_errors 
                                  THEN concat_ws('; ', 'error', err_text, err_detail, err_hint, 'query: ' || query ) 
                                  ELSE COALESCE(v_trigger.cids, '') 
                                END
                                
                              ), 7999/4) -- Some chars are 2bytes -> '╬®'
                            );
                        END LOOP;


                        IF has_errors THEN

                          DELETE FROM prostgles.app_triggers;
                          RAISE NOTICE 'trigger dropped due to exception: % % %', err_text, err_detail, err_hint;

                        END IF;
                        
                    END IF;
                END IF;

                
  /* 
    prostgles query used to keep track of which prgl backend clients are still connected
    prostgles-server internal query used to manage realtime triggers 
    prostgles internal query that should be excluded from schema watch 
  */
  IF
    /* prostgles schema must exist */
    EXISTS (
      SELECT 1 
      FROM information_schema.tables 
      WHERE  table_schema = 'prostgles'
      AND    table_name   = 'apps'
    )
    /* Ensure we don't check in paralel */
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_stat_activity s
      WHERE s.query ilike '%prostgles query used to keep track of which prgl backend clients are still connected%'
      AND s.state = 'active'
    )
  THEN 

    IF EXISTS (
      
  SELECT DISTINCT application_name
  FROM prostgles.apps 
  WHERE application_name IN (
    SELECT application_name 
    FROM pg_catalog.pg_stat_activity
  )

    ) THEN

      /* Remove disconnected apps */
      WITH deleted_apps AS (
        
  DELETE FROM prostgles.apps a
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_stat_activity s
    WHERE s.application_name = a.application_name
  )

        RETURNING a.id
      )
      DELETE FROM prostgles.app_triggers
      WHERE app_id IN (
        SELECT id 
        FROM deleted_apps
      );
 
    END IF;
  END IF;


                RETURN NULL;
               
            END;

        $_$;


ALTER FUNCTION prostgles.prostgles_trigger_function() OWNER TO postgres;

--
-- Name: FUNCTION prostgles_trigger_function(); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.prostgles_trigger_function() IS 'Prostgles internal function used to notify when data in the table changed';


--
-- Name: random_string(integer); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.random_string(length integer DEFAULT 33) RETURNS text
    LANGUAGE plpgsql
    AS $$
          DECLARE 
              chars TEXT[] := '{0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z,a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z}';
              result TEXT := '';
              i INTEGER := 0;
          BEGIN

            IF length < 0 THEN
                RAISE exception 'Given length cannot be less than 0';
            END IF;

            FOR i IN 1..length LOOP
                result := result || chars[1+random()*(array_length(chars, 1)-1)];
            END LOOP;

            RETURN result;

          END;
        $$;


ALTER FUNCTION prostgles.random_string(length integer) OWNER TO postgres;

--
-- Name: FUNCTION random_string(length integer); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.random_string(length integer) IS 'UUIDs without installing pgcrypto';


--
-- Name: schema_watch_func(); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.schema_watch_func() RETURNS event_trigger
    LANGUAGE plpgsql
    AS $_$
            
            DECLARE curr_query TEXT := '';                                       
            DECLARE app RECORD;
            DECLARE objects_changed BOOLEAN := false;   
            
            BEGIN

                IF TG_event = 'ddl_command_end' THEN
                  objects_changed := EXISTS (
                    SELECT * 
                    FROM pg_event_trigger_ddl_commands()
                  );
                END IF;
                IF TG_event = 'sql_drop' THEN
                  objects_changed := EXISTS (
                    SELECT * 
                    FROM pg_event_trigger_dropped_objects()
                  );
                END IF;
    
                /* 
                  This event trigger will outlive a prostgles app instance. 
                  Must ensure it only fires if an app instance is running  
                */
                IF
                  objects_changed 
                  AND EXISTS (
                    SELECT 1 
                    FROM information_schema.tables 
                    WHERE  table_schema = 'prostgles'
                    AND    table_name   = 'apps'
                  )          
                THEN

                    SELECT LEFT(COALESCE(current_query(), ''), 5000)
                    INTO curr_query;
                    
                    FOR app IN 
                      SELECT * 
                      FROM prostgles.apps 
                      WHERE tg_tag = ANY(watching_schema_tag_names)
                      AND curr_query NOT ILIKE '%prostgles internal query that should be excluded from schema watch %'
                    LOOP
                      PERFORM pg_notify( 
                        'prostgles_' || app.id, 
                        LEFT(concat_ws(
                          '|$prstgls$|', 
                          'schema_has_changed', 
                          tg_tag , 
                          TG_event, 
                          'Only shown in debug mode'
                        ), 7999/4)
                      );
                    END LOOP;

                    
  /* 
    prostgles query used to keep track of which prgl backend clients are still connected
    prostgles-server internal query used to manage realtime triggers 
    prostgles internal query that should be excluded from schema watch 
  */
  IF
    /* prostgles schema must exist */
    EXISTS (
      SELECT 1 
      FROM information_schema.tables 
      WHERE  table_schema = 'prostgles'
      AND    table_name   = 'apps'
    )
    /* Ensure we don't check in paralel */
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_stat_activity s
      WHERE s.query ilike '%prostgles query used to keep track of which prgl backend clients are still connected%'
      AND s.state = 'active'
    )
  THEN 

    IF EXISTS (
      
  SELECT DISTINCT application_name
  FROM prostgles.apps 
  WHERE application_name IN (
    SELECT application_name 
    FROM pg_catalog.pg_stat_activity
  )

    ) THEN

      /* Remove disconnected apps */
      WITH deleted_apps AS (
        
  DELETE FROM prostgles.apps a
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_stat_activity s
    WHERE s.application_name = a.application_name
  )

        RETURNING a.id
      )
      DELETE FROM prostgles.app_triggers
      WHERE app_id IN (
        SELECT id 
        FROM deleted_apps
      );
 
    END IF;
  END IF;


                END IF;

            END;
        $_$;


ALTER FUNCTION prostgles.schema_watch_func() OWNER TO postgres;

--
-- Name: FUNCTION schema_watch_func(); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.schema_watch_func() IS 'Prostgles internal function used to notify when schema has changed';


--
-- Name: trigger_add_remove_func(); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.trigger_add_remove_func() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$

            DECLARE operations TEXT[] := ARRAY['insert', 'update', 'delete'];
            DECLARE op TEXT;
            DECLARE query TEXT;
            DECLARE trg_name TEXT;
            DECLARE trw RECORD;           
            DECLARE app RECORD; 
            DECLARE start_time BIGINT;
            DECLARE changed_triggers_count integer;        
            
            BEGIN
                
                start_time := EXTRACT(EPOCH FROM now()) * 1000;

                --RAISE NOTICE 'prostgles.app_triggers % ', TG_OP;

                /* If no other listeners (app_triggers) left on table then DISABLE actual table data watch triggers */
                IF TG_OP = 'DELETE' THEN

                    --RAISE NOTICE 'DELETE trigger_add_remove_func table: % ', ' ' || COALESCE((SELECT concat_ws(' ', string_agg(table_name, ' & '), count(*), min(inserted) ) FROM prostgles.app_triggers) , ' 0 ');
                    --RAISE NOTICE 'DELETE trigger_add_remove_func old_table:  % ', '' || COALESCE((SELECT concat_ws(' ', string_agg(table_name, ' & '), count(*), min(inserted) ) FROM old_table), ' 0 ');
                    
                    SELECT count(*) 
                    FROM old_table 
                    INTO changed_triggers_count;
                    
                    /* Disable actual triggers if needed */
                    FOR trw IN 
                        SELECT DISTINCT table_name 
                        FROM old_table ot
                        WHERE NOT EXISTS (
                          SELECT 1 
                          FROM prostgles.app_triggers t 
                          WHERE t.table_name = ot.table_name
                        )
                        AND EXISTS (
                          SELECT trigger_name 
                          FROM information_schema.triggers 
                          WHERE trigger_name IN (
                            concat_ws('_', 'prostgles_triggers', table_name, 'insert'),
                            concat_ws('_', 'prostgles_triggers', table_name, 'update'),
                            concat_ws('_', 'prostgles_triggers', table_name, 'delete')
                          )
                        )
                    LOOP

                        FOREACH op IN ARRAY operations
                        LOOP 
                            trg_name := concat_ws('_', 'prostgles_triggers', trw.table_name, op);
                             
                            EXECUTE format(' ALTER TABLE %s DISABLE TRIGGER %I ;', trw.table_name, trg_name);
                        END LOOP;
                                      
                    END LOOP;

                /* If newly added listeners on table then CREATE table data watch triggers */
                ELSIF TG_OP = 'INSERT' THEN
                      
                    SELECT count(*) 
                    FROM new_table 
                    INTO changed_triggers_count;
 
                    /* Loop through newly added tables to add data watch triggers */
                    FOR trw IN  

                        SELECT DISTINCT table_name 
                        FROM new_table nt

                        /* Table did not exist prior to this insert */
                        WHERE NOT EXISTS (
                            SELECT 1 
                            FROM prostgles.app_triggers t 
                            WHERE t.table_name = nt.table_name
                            AND   t.inserted   < nt.inserted    -- exclude current record (this is an after trigger). Turn into before trigger?
                        )

                        /* Table is valid 
                        AND  EXISTS (
                            SELECT 1 
                            FROM information_schema.tables 
                            WHERE  table_schema = 'public'
                            AND    table_name   = nt.table_name
                        )
                        */
                    LOOP

                        IF (
                          SELECT COUNT(*) 
                          FROM information_schema.triggers
                          WHERE trigger_name IN (
                            'prostgles_triggers_' || trw.table_name || '_insert',
                            'prostgles_triggers_' || trw.table_name || '_update',
                            'prostgles_triggers_' || trw.table_name || '_delete'
                          )
                        ) = 3
                        THEN
                          query := concat_ws(E'
', 
                            format(' ALTER TABLE %s ENABLE TRIGGER %I ;', trw.table_name, 'prostgles_triggers_' || trw.table_name || '_insert'),
                            format(' ALTER TABLE %s ENABLE TRIGGER %I ;', trw.table_name, 'prostgles_triggers_' || trw.table_name || '_update'),
                            format(' ALTER TABLE %s ENABLE TRIGGER %I ;', trw.table_name, 'prostgles_triggers_' || trw.table_name || '_delete')
                          );
                        ELSE 

                          query := format(
                              $q$ 
                                  CREATE OR REPLACE TRIGGER %1$I
                                  AFTER INSERT ON %2$s
                                  REFERENCING NEW TABLE AS new_table
                                  FOR EACH STATEMENT EXECUTE PROCEDURE prostgles.prostgles_trigger_function();
                                  /* removed to allow less privileges for a user to create subscriptions
                                    COMMENT ON TRIGGER %1$I ON %2$s IS 'Prostgles internal trigger used to notify when data in the table changed';
                                  */
                              $q$,  
                              'prostgles_triggers_' || trw.table_name || '_insert', trw.table_name                                                
                          ) || format(
                              $q$ 
                                  CREATE OR REPLACE TRIGGER %1$I
                                  AFTER UPDATE ON %2$s
                                  REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table
                                  FOR EACH STATEMENT EXECUTE PROCEDURE prostgles.prostgles_trigger_function();
                                  --COMMENT ON TRIGGER %1$I ON %2$s IS 'Prostgles internal trigger used to notify when data in the table changed';
                              $q$,  
                              'prostgles_triggers_' || trw.table_name || '_update', trw.table_name   
                          ) || format(
                              $q$ 
                                  CREATE OR REPLACE TRIGGER %1$I
                                  AFTER DELETE ON %2$s
                                  REFERENCING OLD TABLE AS old_table
                                  FOR EACH STATEMENT EXECUTE PROCEDURE prostgles.prostgles_trigger_function();
                                  --COMMENT ON TRIGGER %1$I ON %2$s IS 'Prostgles internal trigger used to notify when data in the table changed';
                              $q$,
                              'prostgles_triggers_' || trw.table_name || '_delete', trw.table_name  
                          );
                        END IF;


                        --RAISE NOTICE ' % ', query;

                        
                        query := format(
                            $q$
                                DO $e$ 
                                BEGIN
                                    /* prostgles internal query that should be excluded from schema watch  */
                                    %s

                                END $e$;
                            $q$,
                            query
                        ) ;
                        

                        EXECUTE query;
                                    
                    END LOOP;

                END IF;

                /** Notify all apps about trigger table change */
                IF changed_triggers_count > 0 THEN
                  FOR app IN 
                    SELECT * FROM prostgles.apps
                  LOOP
                    PERFORM pg_notify( 
                      'prostgles_' || app.id, 
                      LEFT(concat_ws(
                        '|$prstgls$|', 
                        'data_watch_triggers_have_changed',
                        json_build_object(
                          'TG_OP', TG_OP, 
                          'duration', (EXTRACT(EPOCH FROM now()) * 1000) - start_time,
                          'query', 'Only shown in debug mode'
                        )
                      )::TEXT, 7999/4)
                    );
                  END LOOP;
                END IF;

                RETURN NULL;
            END;

        $_$;


ALTER FUNCTION prostgles.trigger_add_remove_func() OWNER TO postgres;

--
-- Name: FUNCTION trigger_add_remove_func(); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.trigger_add_remove_func() IS 'Used to add/remove table watch triggers concurrently ';


--
-- Name: user(text); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles."user"(key text DEFAULT NULL::text) RETURNS text
    LANGUAGE plpgsql
    AS $$
        DECLARE user_text text;
        DECLARE user_jsonb JSONB = '{}'::JSONB;
        BEGIN
          user_text := current_setting('prostgles.user', true);
          IF length(user_text) > 0 THEN
            user_jsonb := user_text::JSONB;
          END IF;
        
          IF length(key) > 0 THEN
            RETURN jsonb_extract_path(user_jsonb, key);
          END IF;
          RETURN user_jsonb;
        END;
        $$;


ALTER FUNCTION prostgles."user"(key text) OWNER TO postgres;

--
-- Name: FUNCTION "user"(key text); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles."user"(key text) IS 'Used for row level security';


--
-- Name: user_id(); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.user_id() RETURNS uuid
    LANGUAGE plpgsql
    AS $$ 
        BEGIN
          RETURN prostgles.user('id')::UUID;
        END;
        $$;


ALTER FUNCTION prostgles.user_id() OWNER TO postgres;

--
-- Name: FUNCTION user_id(); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.user_id() IS 'Session user id';


--
-- Name: user_type(); Type: FUNCTION; Schema: prostgles; Owner: postgres
--

CREATE FUNCTION prostgles.user_type() RETURNS text
    LANGUAGE plpgsql
    AS $$ 
        BEGIN
          RETURN prostgles.user('type')::TEXT;
        END;
        $$;


ALTER FUNCTION prostgles.user_type() OWNER TO postgres;

--
-- Name: FUNCTION user_type(); Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON FUNCTION prostgles.user_type() IS 'Session user type';


--
-- Name: Update updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."Update updated_at"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  
              
          BEGIN
            NEW.updated_at = now();
            RETURN NEW;
          END;
        
              
              $$;


ALTER FUNCTION public."Update updated_at"() OWNER TO postgres;

--
-- Name: atLeastOneActiveAdmin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."atLeastOneActiveAdmin"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  
              
          BEGIN
            IF NOT EXISTS(SELECT * FROM users WHERE type = 'admin' AND status = 'active') THEN
              RAISE EXCEPTION 'Must have at least one active admin user';
            END IF;

            RETURN NULL;
          END;
        
              
              $$;


ALTER FUNCTION public."atLeastOneActiveAdmin"() OWNER TO postgres;

--
-- Name: atLeastOneAdminAndPublic(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public."atLeastOneAdminAndPublic"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  
               
          BEGIN
            IF NOT EXISTS(SELECT * FROM user_types WHERE id = 'admin') 
              OR NOT EXISTS(SELECT * FROM user_types WHERE id = 'public')
            THEN
              RAISE EXCEPTION 'admin and public user types cannot be deleted/modified';
            END IF;
  
            RETURN NULL;
          END;
        
              
              $$;


ALTER FUNCTION public."atLeastOneAdminAndPublic"() OWNER TO postgres;

--
-- Name: validate_jsonb_schema(text, jsonb, jsonb, text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_jsonb_schema(jsonb_schema text, data jsonb, context jsonb DEFAULT '{}'::jsonb, checked_path text[] DEFAULT ARRAY[]::text[]) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
  sub_schema RECORD;
  array_element RECORD;
  obj_key_val RECORD;
  schema JSONB;
  path text;
  allowed_types text[] = '{boolean,number,integer,string,Date,time,timestamp,any,boolean[],number[],integer[],string[],Date[],time[],timestamp[],any[],Lookup,Lookup[]}';
  typeStr TEXT = NULL; 
  optional boolean;
  nullable boolean; 
  colname TEXT = COALESCE(context->>'column', '');
  tablename TEXT = COALESCE(context->>'table', '');
  oneof JSONB;
  arrayof JSONB;
  lookup_data_def_schema TEXT = $d$  
    { 
      "type": { "enum": ["data", "data-def"] },
      "table": "string",
      "column": "string",
      "lookup": { "type": "any", "optional": true },
      "isArray": { "type": "boolean", "optional": true },
      "filter": { "optional": true, "type": "any" },
      "isFullRow": { "optional": true, "type": {
        "displayColumns": { "optional": true, "type": "string[]" }
      }},
      "searchColumns": { "optional": true, "type": "string[]" },
      "showInRowCard": { "optional": true, "type": "any" }
    }  
  
  $d$;
  lookup_schema_schema TEXT = $d$  
    { 
      "type": { "enum": ["schema"] },
      "object": { "enum": ["table", "column"] },
      "isArray": { "type": "boolean", "optional": true },
      "lookup": { "type": "any", "optional": true },
      "filter": { "optional": true, "type": "any" }
    }  
  $d$;

  extra_keys TEXT[];

  /* Used for oneOf schema errors */
  v_state   TEXT;
  v_msg     TEXT;
  v_detail  TEXT;
  v_hint    TEXT;
  v_context TEXT;
  v_one_of_errors TEXT;

BEGIN
  path = concat_ws(', ', 
    'Path: ' || array_to_string(checked_path, '.'), 
    'Data: ' || data::TEXT, 
    'JSONBSchema: ' || schema::TEXT
  );

  IF length(jsonb_schema) = 0 THEN
    
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Empty schema. %', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;

  END IF;

  /* Sometimes text comes double quoted from jsonb, e.g.: '"string"' */
  jsonb_schema = CASE WHEN jsonb_schema::text ilike '"%"' THEN  LEFT(RIGHT(jsonb_schema::text, -1), -1) ELSE jsonb_schema END;

  /* 'string' */
  IF ARRAY[jsonb_schema] <@ allowed_types THEN
    schema = jsonb_build_object('type', jsonb_schema);
  /* { "type": ... } */ 
  ELSIF BTRIM(replace(jsonb_schema,E'
','')) ILIKE '{%' THEN
    schema = jsonb_schema::JSONB;
  ELSE
    
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION $$Invalid schema. Expecting 'typename' or { "type": "typename" } but received: %, %$$, jsonb_schema, path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
 
  END IF;


  nullable = COALESCE((schema->>'nullable')::BOOLEAN, FALSE);
  IF data IS NULL OR jsonb_typeof(data) = 'null' THEN
    IF NOT nullable THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Is not nullable. %', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    ELSE
      RETURN true;
    END IF;
  END IF;
  
  IF schema ? 'enum' THEN 
    IF 
      jsonb_typeof(schema->'enum') != 'array' OR 
      jsonb_array_length(schema->'enum') < 1 
    THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Invalid schema enum (%) .Must be a non empty array %', schema->'enum', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF;
    
    IF NOT jsonb_build_array(data) <@ (schema->'enum') THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Data not in allowed enum list (%), %', schema->'enum', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF;

  ELSIF schema ? 'lookup' THEN

    /* TODO: Finish validating data-def */
    IF (schema->'lookup'->>'type' = 'data-def') THEN
      RETURN TRUE;
    END IF;

    /* Validate lookup schema */
    IF NOT validate_jsonb_schema(
      '{ "oneOfType": [' || concat_ws(',',lookup_data_def_schema, lookup_schema_schema)  || '] }',
      schema->'lookup',
      context,
      checked_path || '.schema'::TEXT
    ) THEN
      
      RETURN FALSE;
    END IF;

    RETURN validate_jsonb_schema(
      CASE WHEN schema->'lookup'->>'type' = 'data-def' THEN
        lookup_data_def_schema
      WHEN schema->'lookup'->>'type' = 'schema' THEN 
        ( 
          CASE WHEN schema->'lookup'->>'object' = 'table' THEN 
            'string' || (CASE WHEN (schema->'lookup'->'isArray')::BOOLEAN THEN '[]' ELSE '' END)
          ELSE 
            '{ "type": { "table": "string", "column": "string' || (CASE WHEN (schema->'lookup'->'isArray')::BOOLEAN THEN '[]' ELSE '' END) || '" } }' 
          END
        )
      ELSE 
        (CASE WHEN (schema->'lookup'->'isArray')::BOOLEAN THEN 'any[]' ELSE 'any' END)
      END,
      data,
      context,
      checked_path
    );

  ELSIF schema ? 'type' THEN    
    
    IF jsonb_typeof(schema->'type') = 'string' THEN
      typeStr = schema->>'type';
      IF NOT ARRAY[typeStr] <@ allowed_types THEN
        
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Bad schema type "%", allowed types: %. %',typeStr, allowed_types, path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
      END IF;
      
      /** Primitive array */
      IF typeStr LIKE '%[]' THEN
 
        typeStr = left(typeStr, -2);

        IF jsonb_typeof(data) != 'array' THEN
          
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Types not matching. Expecting an array. %', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
        END IF;

        FOR array_element IN
          SELECT value, row_number() OVER() -1 as idx
          FROM jsonb_array_elements(data)
        LOOP
          IF NOT validate_jsonb_schema(
              CASE WHEN schema->'allowedValues' IS NOT NULL THEN 
                jsonb_build_object('type', typeStr, 'allowedValues', schema->'allowedValues')::TEXT
              ELSE typeStr END, 
              array_element.value, 
              context,
              checked_path || array_element.idx::TEXT
          ) THEN
            
            RETURN FALSE;
          END IF;
        END LOOP;

        RETURN TRUE;

      /** Primitive */
      ELSE 

        IF (
          typeStr = 'number' AND jsonb_typeof(data) != typeStr OR
          (typeStr = 'integer' AND (jsonb_typeof(data) != 'number' OR ceil(data::NUMERIC) != floor(data::NUMERIC))) OR
          typeStr = 'boolean' AND jsonb_typeof(data) != typeStr OR
          typeStr = 'string' AND jsonb_typeof(data) != typeStr OR
          typeStr = 'any' AND jsonb_typeof(data) = 'null'
        ) THEN
          
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Data type not matching. Expected: %, Actual: %, %', typeStr, jsonb_typeof(data), path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
        END IF;

        IF schema ? 'allowedValues' AND NOT(jsonb_build_array(data) <@ (schema->'allowedValues')) THEN
          IF (
            SELECT COUNT(distinct jsonb_typeof(value))
            FROM jsonb_array_elements(schema->'allowedValues')
          ) > 1 THEN
            
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Invalid schema. schema.allowedValues (%) contains more than one data type . %', schema->>'allowedValues', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
          END IF;

          IF EXISTS(
            SELECT 1
            FROM jsonb_array_elements(schema->'allowedValues')
            WHERE jsonb_typeof(value) != jsonb_typeof(data)
          ) THEN
            
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Invalid schema. schema.allowedValues (%) contains contains values not matchine the schema.type %', schema->>'allowedValues', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
          END IF;

          
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Data not in allowedValues (%). %', schema->>'allowedValues', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  

        END IF;

      END IF;

    /* Object */
    ELSIF jsonb_typeof(schema->'type') = 'object' THEN

      IF jsonb_typeof(data) != 'object' THEN
        
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION E'Expecting an object: 
 %', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
      END IF;

      extra_keys = ARRAY(SELECT k FROM (
        SELECT jsonb_object_keys(data) as k
        EXCEPT
        SELECT jsonb_object_keys(schema->'type') as k
      ) t);

      IF array_length(extra_keys, 1) > 0 THEN
        
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION E'Object contains % invalid keys: [ % ] 
 %', array_length(extra_keys, 1)::TEXT, array_to_string(extra_keys, ', '), path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
      END IF;
      
      FOR sub_schema IN
        SELECT key, value
        FROM jsonb_each(schema->'type')
      LOOP

        optional = COALESCE((sub_schema.value->>'optional')::BOOLEAN, FALSE);
        IF NOT (data ? sub_schema.key) THEN
          IF NOT optional THEN
            
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Types not matching. Required property ("%") is missing. %', sub_schema.key , path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
          END IF;

        ELSIF NOT validate_jsonb_schema(
          -- sub_schema.value::TEXT, 
          CASE WHEN jsonb_typeof(sub_schema.value) = 'string' THEN TRIM(both '"' from sub_schema.value::TEXT) ELSE sub_schema.value::TEXT END,
          data->sub_schema.key, 
          context,
          checked_path || sub_schema.key
        ) THEN
          RETURN false;
        END IF;

      END LOOP;

      RETURN TRUE;
    ELSE 
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Unexpected schema.type ( % ), %',jsonb_typeof(schema->'type'), path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF; 

  /* oneOfType: [{ key_name: { type: "string" } }] */
  ELSIF (schema ? 'oneOf' OR schema ? 'oneOfType') THEN 

    oneof = COALESCE(schema->'oneOf', schema->'oneOfType');

    IF jsonb_typeof(oneof) != 'array' THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Unexpected oneOf schema. Expecting an array of objects but received: % , %', oneof::TEXT, path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF;

    FOR sub_schema IN
      SELECT CASE WHEN schema ? 'oneOfType' THEN jsonb_build_object('type', value) ELSE value END as value, 
        row_number() over() - 1 as idx
      FROM jsonb_array_elements(oneof)
    LOOP

      BEGIN

        IF validate_jsonb_schema(
          sub_schema.value::TEXT, 
          data, 
          context,
          checked_path
        ) THEN
          RETURN true;
        END IF;

      /* Ignore exceptions in case the last schema will match */
      EXCEPTION WHEN others THEN

        GET STACKED DIAGNOSTICS
          v_state   = returned_sqlstate,
          v_msg     = message_text,
          v_detail  = pg_exception_detail,
          v_hint    = pg_exception_hint,
          v_context = pg_exception_context;

        /* Ignore duplicate errors */
        IF v_one_of_errors IS NULL OR v_one_of_errors NOT ilike '%' || v_msg || '%' THEN
          v_one_of_errors = concat_ws(
            E'

', 
            v_one_of_errors,  
            concat_ws(
              ', ', 
              'Schema index ' || sub_schema.idx::TEXT || ' error:', 
              'state: ' || v_state, 
              'message: ' || v_msg,
              'detail: ' || v_detail,
              'hint: ' || v_hint
              -- 'context: ' || v_context
            )
          );
        END IF;
      END;

    END LOOP;

    
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION E'No oneOf schemas matching:
  % ), %', v_one_of_errors, path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  

  /* arrayOfType: { key_name: { type: "string" } } */
  ELSIF (schema ? 'arrayOf' OR schema ? 'arrayOfType') THEN

    arrayof = COALESCE(schema->'arrayOf', schema->'arrayOfType');

    IF jsonb_typeof(data) != 'array' THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION '% is not an array.', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF;

    FOR array_element IN 
      SELECT value, row_number() OVER() -1 as idx  
      FROM jsonb_array_elements(data)
    LOOP
      IF NOT validate_jsonb_schema(
        ( CASE WHEN schema ? 'arrayOf' 
          THEN 
            schema->'arrayOf' 
          ELSE 
          (schema - 'arrayOfType' || jsonb_build_object('type', schema->'arrayOfType')) 
          END
        )::TEXT,
        array_element.value, 
        context,
        checked_path || array_element.idx::TEXT
      ) THEN
        RETURN false;
      END IF; 
    END LOOP;
  
  /* record: { keysEnum?: string[], values?: FieldType } */
  ELSIF schema ? 'record' THEN
    IF 
      jsonb_typeof(schema->'record') != 'object' OR 
      NOT (schema->'record') ? 'keysEnum' 
      AND NOT (schema->'record') ? 'values'
    THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Invalid/empty record schema. Expecting a non empty record of: { keysEnum?: string[]; values?: FieldType } : %, %', schema, path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF;

    IF jsonb_typeof(data) != 'object' THEN
      
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION '% is not an object.', path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;
  
    END IF;

    FOR obj_key_val IN
      SELECT jsonb_build_object('key',  key, 'value', value) as obj
      FROM jsonb_each(data)
    LOOP
      RETURN (CASE WHEN NOT (schema->'record') ? 'keysEnum' THEN TRUE ELSE validate_jsonb_schema( 
        jsonb_build_object('enum', schema->'record'->'keysEnum')::TEXT,
        (obj_key_val.obj)->'key', 
        context,
        checked_path || ARRAY[(obj_key_val.obj)->>'key']
      ) END) 
      AND 
      (CASE WHEN NOT (schema->'record') ? 'values' THEN TRUE ELSE validate_jsonb_schema(
        schema->'record'->>'values', 
        (obj_key_val.obj)->'value', 
        context,
        checked_path || ARRAY[(obj_key_val.obj)->>'key']
      ) END);
    END LOOP;

  ELSE
    
IF (context->'silent')::BOOLEAN = TRUE THEN
  RETURN FALSE;
ELSE
  RAISE EXCEPTION 'Unexpected schema: %, %', schema, path USING HINT = path, COLUMN = colname, TABLE = tablename, CONSTRAINT = 'validate_jsonb_schema: ' || jsonb_pretty(jsonb_schema::JSONB);
END IF;

  END IF;
  
  RETURN true;
END;
$_$;


ALTER FUNCTION public.validate_jsonb_schema(jsonb_schema text, data jsonb, context jsonb, checked_path text[]) OWNER TO postgres;

--
-- Name: FUNCTION validate_jsonb_schema(jsonb_schema text, data jsonb, context jsonb, checked_path text[]); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_jsonb_schema(jsonb_schema text, data jsonb, context jsonb, checked_path text[]) IS 'prostgles-server internal function used in column CHECK conditions to validate jsonb data against a column schema specified in tableConfig.
Example usage:
validate_jsonb_schema(
  ''{ "type": { "a": "number[]" } }'', 
  ''{ "a": [2] }''
)
';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: app_triggers; Type: TABLE; Schema: prostgles; Owner: postgres
--

CREATE TABLE prostgles.app_triggers (
    app_id text NOT NULL,
    table_name text NOT NULL,
    condition text NOT NULL,
    condition_hash text NOT NULL,
    related_view_name text,
    related_view_def text,
    inserted timestamp without time zone DEFAULT now() NOT NULL,
    last_used timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE prostgles.app_triggers OWNER TO postgres;

--
-- Name: TABLE app_triggers; Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON TABLE prostgles.app_triggers IS 'Tables and conditions that are currently subscribed/synced';


--
-- Name: apps; Type: TABLE; Schema: prostgles; Owner: postgres
--

CREATE TABLE prostgles.apps (
    id text DEFAULT prostgles.random_string() NOT NULL,
    added timestamp without time zone DEFAULT now(),
    application_name text,
    watching_schema_tag_names text[],
    check_frequency_ms integer NOT NULL
);


ALTER TABLE prostgles.apps OWNER TO postgres;

--
-- Name: TABLE apps; Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON TABLE prostgles.apps IS 'Keep track of prostgles server apps connected to db to combine common triggers. Heartbeat used due to no logout triggers in postgres';


--
-- Name: v_triggers; Type: VIEW; Schema: prostgles; Owner: postgres
--

CREATE VIEW prostgles.v_triggers AS
 SELECT app_id,
    table_name,
    condition,
    condition_hash,
    related_view_name,
    related_view_def,
    inserted,
    last_used,
    (row_number() OVER (ORDER BY table_name, condition))::text AS id,
    (row_number() OVER (PARTITION BY app_id, table_name ORDER BY table_name, condition) - 1) AS c_id
   FROM prostgles.app_triggers;


ALTER VIEW prostgles.v_triggers OWNER TO postgres;

--
-- Name: VIEW v_triggers; Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON VIEW prostgles.v_triggers IS 'Augment trigger table with natural IDs and per app IDs';


--
-- Name: versions; Type: TABLE; Schema: prostgles; Owner: postgres
--

CREATE TABLE prostgles.versions (
    version text NOT NULL,
    schema_md5 text NOT NULL,
    added_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE prostgles.versions OWNER TO postgres;

--
-- Name: TABLE versions; Type: COMMENT; Schema: prostgles; Owner: postgres
--

COMMENT ON TABLE prostgles.versions IS 'Stores the prostgles schema creation query hash and package version number to identify when a newer schema needs to be re-created';


--
-- Name: access_control; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.access_control (
    id integer NOT NULL,
    name text,
    database_id integer NOT NULL,
    llm_daily_limit integer DEFAULT 0 NOT NULL,
    "dbsPermissions" jsonb,
    "dbPermissions" jsonb NOT NULL,
    created timestamp without time zone DEFAULT now(),
    CONSTRAINT "access_control_dbPermissions_check" CHECK (public.validate_jsonb_schema('{"info":{"hint":"Permission types and rules for this (connection_id) database"},"oneOfType":[{"type":{"enum":["Run SQL"],"description":"Allows complete access to the database"},"allowSQL":{"type":"boolean","optional":true}},{"type":{"enum":["All views/tables"],"description":"Custom access (View/Edit/Remove) to all tables"},"allowAllTables":{"type":"string[]","allowedValues":["select","insert","update","delete"]}},{"type":{"enum":["Custom"],"description":"Fine grained access to specific tables"},"customTables":{"arrayOfType":{"tableName":"string","select":{"optional":true,"description":"Allows viewing data","oneOf":["boolean",{"type":{"fields":{"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"forcedFilterDetailed":{"optional":true,"type":"any"},"subscribe":{"optional":true,"type":{"throttle":{"optional":true,"type":"integer"}}},"filterFields":{"optional":true,"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"orderByFields":{"optional":true,"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]}}}]},"update":{"optional":true,"oneOf":["boolean",{"type":{"fields":{"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"forcedFilterDetailed":{"optional":true,"type":"any"},"checkFilterDetailed":{"optional":true,"type":"any"},"filterFields":{"optional":true,"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"orderByFields":{"optional":true,"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"forcedDataDetail":{"optional":true,"type":"any[]"},"dynamicFields":{"optional":true,"arrayOfType":{"filterDetailed":"any","fields":{"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]}}}}}]},"insert":{"optional":true,"oneOf":["boolean",{"type":{"fields":{"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"forcedDataDetail":{"optional":true,"type":"any[]"},"checkFilterDetailed":{"optional":true,"type":"any"}}}]},"delete":{"optional":true,"oneOf":["boolean",{"type":{"filterFields":{"oneOf":["string[]",{"enum":["*",""]},{"record":{"values":{"enum":[1,true]}}},{"record":{"values":{"enum":[0,false]}}}]},"forcedFilterDetailed":{"optional":true,"type":"any"}}}]},"sync":{"optional":true,"type":{"id_fields":{"type":"string[]"},"synced_field":{"type":"string"},"throttle":{"optional":true,"type":"integer"},"allow_delete":{"type":"boolean","optional":true}}}}}}]}'::text, "dbPermissions", '{"table": "access_control", "column": "dbPermissions"}'::jsonb)),
    CONSTRAINT "access_control_dbsPermissions_check" CHECK (public.validate_jsonb_schema('{"nullable":true,"info":{"hint":"Permission types and rules for the state database"},"type":{"createWorkspaces":{"type":"boolean","optional":true},"viewPublishedWorkspaces":{"optional":true,"type":{"workspaceIds":"string[]"}}}}'::text, "dbsPermissions", '{"table": "access_control", "column": "dbsPermissions"}'::jsonb)),
    CONSTRAINT access_control_llm_daily_limit_check CHECK ((llm_daily_limit >= 0))
);


ALTER TABLE public.access_control OWNER TO postgres;

--
-- Name: access_control_allowed_llm; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.access_control_allowed_llm (
    access_control_id integer NOT NULL,
    llm_credential_id integer NOT NULL,
    llm_prompt_id integer NOT NULL
);


ALTER TABLE public.access_control_allowed_llm OWNER TO postgres;

--
-- Name: access_control_connections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.access_control_connections (
    connection_id uuid NOT NULL,
    access_control_id integer NOT NULL
);


ALTER TABLE public.access_control_connections OWNER TO postgres;

--
-- Name: access_control_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.access_control_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.access_control_id_seq OWNER TO postgres;

--
-- Name: access_control_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.access_control_id_seq OWNED BY public.access_control.id;


--
-- Name: access_control_methods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.access_control_methods (
    published_method_id integer NOT NULL,
    access_control_id integer NOT NULL
);


ALTER TABLE public.access_control_methods OWNER TO postgres;

--
-- Name: access_control_user_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.access_control_user_types (
    access_control_id integer NOT NULL,
    user_type text NOT NULL
);


ALTER TABLE public.access_control_user_types OWNER TO postgres;

--
-- Name: alert_viewed_by; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alert_viewed_by (
    id bigint NOT NULL,
    alert_id bigint,
    user_id uuid,
    viewed timestamp without time zone DEFAULT now()
);


ALTER TABLE public.alert_viewed_by OWNER TO postgres;

--
-- Name: alert_viewed_by_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.alert_viewed_by_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alert_viewed_by_id_seq OWNER TO postgres;

--
-- Name: alert_viewed_by_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.alert_viewed_by_id_seq OWNED BY public.alert_viewed_by.id;


--
-- Name: alerts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alerts (
    id bigint NOT NULL,
    title text,
    message text,
    severity text NOT NULL,
    database_config_id integer,
    connection_id uuid,
    section text,
    data jsonb,
    created timestamp without time zone DEFAULT now(),
    CONSTRAINT alerts_section_check CHECK (((section = 'access_control'::text) OR (section = 'backups'::text) OR (section = 'table_config'::text) OR (section = 'details'::text) OR (section = 'status'::text) OR (section = 'methods'::text) OR (section = 'file_storage'::text) OR (section = 'API'::text))),
    CONSTRAINT alerts_severity_check CHECK (((severity = 'info'::text) OR (severity = 'warning'::text) OR (severity = 'error'::text)))
);


ALTER TABLE public.alerts OWNER TO postgres;

--
-- Name: alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alerts_id_seq OWNER TO postgres;

--
-- Name: alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.alerts_id_seq OWNED BY public.alerts.id;


--
-- Name: backups; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.backups (
    id text DEFAULT gen_random_uuid() NOT NULL,
    connection_id uuid,
    connection_details text DEFAULT 'unknown connection'::text NOT NULL,
    credential_id integer,
    destination text NOT NULL,
    dump_command text NOT NULL,
    restore_command text,
    local_filepath text,
    content_type text DEFAULT 'application/gzip'::text NOT NULL,
    initiator text,
    details jsonb,
    status jsonb NOT NULL,
    uploaded timestamp without time zone,
    restore_status jsonb,
    restore_start timestamp without time zone,
    restore_end timestamp without time zone,
    restore_logs text,
    dump_logs text,
    "dbSizeInBytes" bigint NOT NULL,
    "sizeInBytes" bigint,
    created timestamp without time zone DEFAULT now() NOT NULL,
    last_updated timestamp without time zone DEFAULT now() NOT NULL,
    options jsonb NOT NULL,
    restore_options jsonb DEFAULT '{"clean": true, "format": "c", "command": "pg_restore"}'::jsonb NOT NULL,
    CONSTRAINT backups_destination_check CHECK (((destination = 'Local'::text) OR (destination = 'Cloud'::text) OR (destination = 'None (temp stream)'::text))),
    CONSTRAINT backups_options_check CHECK (public.validate_jsonb_schema('{"oneOfType":[{"command":{"enum":["pg_dumpall"]},"clean":{"type":"boolean"},"dataOnly":{"type":"boolean","optional":true},"globalsOnly":{"type":"boolean","optional":true},"rolesOnly":{"type":"boolean","optional":true},"schemaOnly":{"type":"boolean","optional":true},"ifExists":{"type":"boolean","optional":true},"encoding":{"type":"string","optional":true},"keepLogs":{"type":"boolean","optional":true}},{"command":{"enum":["pg_dump"]},"format":{"enum":["p","t","c"]},"dataOnly":{"type":"boolean","optional":true},"clean":{"type":"boolean","optional":true},"create":{"type":"boolean","optional":true},"encoding":{"type":"string","optional":true},"numberOfJobs":{"type":"integer","optional":true},"noOwner":{"type":"boolean","optional":true},"compressionLevel":{"type":"integer","optional":true},"ifExists":{"type":"boolean","optional":true},"keepLogs":{"type":"boolean","optional":true},"excludeSchema":{"type":"string","optional":true},"schemaOnly":{"type":"boolean","optional":true}}]}'::text, options, '{"table": "backups", "column": "options"}'::jsonb)),
    CONSTRAINT backups_restore_options_check CHECK (public.validate_jsonb_schema('{"type":{"command":{"enum":["pg_restore","psql"]},"format":{"enum":["p","t","c"]},"clean":{"type":"boolean"},"excludeSchema":{"type":"string","optional":true},"newDbName":{"type":"string","optional":true},"create":{"type":"boolean","optional":true},"dataOnly":{"type":"boolean","optional":true},"noOwner":{"type":"boolean","optional":true},"numberOfJobs":{"type":"integer","optional":true},"ifExists":{"type":"boolean","optional":true},"keepLogs":{"type":"boolean","optional":true}}}'::text, restore_options, '{"table": "backups", "column": "restore_options"}'::jsonb)),
    CONSTRAINT backups_restore_status_check CHECK (public.validate_jsonb_schema('{"nullable":true,"oneOfType":[{"ok":{"type":"string"}},{"err":{"type":"string"}},{"loading":{"type":{"loaded":{"type":"number"},"total":{"type":"number"}}}}]}'::text, restore_status, '{"table": "backups", "column": "restore_status"}'::jsonb)),
    CONSTRAINT backups_status_check CHECK (public.validate_jsonb_schema('{"oneOfType":[{"ok":{"type":"string"}},{"err":{"type":"string"}},{"loading":{"optional":true,"type":{"loaded":{"type":"number"},"total":{"type":"number","optional":true}}}}]}'::text, status, '{"table": "backups", "column": "status"}'::jsonb))
);


ALTER TABLE public.backups OWNER TO postgres;

--
-- Name: capturas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.capturas (
    id integer NOT NULL,
    codigo character varying(50) NOT NULL,
    item character varying(20) NOT NULL,
    motivo character varying(100) NOT NULL,
    cumple character varying(20) NOT NULL,
    usuario character varying(50) NOT NULL,
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.capturas OWNER TO postgres;

--
-- Name: capturas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.capturas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.capturas_id_seq OWNER TO postgres;

--
-- Name: capturas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.capturas_id_seq OWNED BY public.capturas.id;


--
-- Name: clp_carga_detalle; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clp_carga_detalle (
    id integer NOT NULL,
    clp_carga_id integer NOT NULL,
    codigo_barras character varying(50) NOT NULL,
    item_id integer NOT NULL
);


ALTER TABLE public.clp_carga_detalle OWNER TO postgres;

--
-- Name: clp_carga_detalle_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clp_carga_detalle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clp_carga_detalle_id_seq OWNER TO postgres;

--
-- Name: clp_carga_detalle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clp_carga_detalle_id_seq OWNED BY public.clp_carga_detalle.id;


--
-- Name: clp_cargas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clp_cargas (
    id integer NOT NULL,
    archivo character varying(255) NOT NULL,
    usuario character varying(50) NOT NULL,
    fecha_carga timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    codigos_agregados integer DEFAULT 0
);


ALTER TABLE public.clp_cargas OWNER TO postgres;

--
-- Name: clp_cargas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clp_cargas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clp_cargas_id_seq OWNER TO postgres;

--
-- Name: clp_cargas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clp_cargas_id_seq OWNED BY public.clp_cargas.id;


--
-- Name: codigos_barras; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.codigos_barras (
    id integer NOT NULL,
    codigo_barras character varying(50) NOT NULL,
    item_id integer NOT NULL
);


ALTER TABLE public.codigos_barras OWNER TO postgres;

--
-- Name: codigos_barras_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.codigos_barras_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.codigos_barras_id_seq OWNER TO postgres;

--
-- Name: codigos_barras_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.codigos_barras_id_seq OWNED BY public.codigos_barras.id;


--
-- Name: codigos_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.codigos_items (
    id integer NOT NULL,
    codigo_barras character varying(50) NOT NULL,
    item character varying(20) NOT NULL,
    resultado text,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.codigos_items OWNER TO postgres;

--
-- Name: codigos_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.codigos_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.codigos_items_id_seq OWNER TO postgres;

--
-- Name: codigos_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.codigos_items_id_seq OWNED BY public.codigos_items.id;


--
-- Name: configuracion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.configuracion (
    id integer NOT NULL,
    clave character varying(100) NOT NULL,
    valor text,
    descripcion text,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.configuracion OWNER TO postgres;

--
-- Name: configuracion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.configuracion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.configuracion_id_seq OWNER TO postgres;

--
-- Name: configuracion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.configuracion_id_seq OWNED BY public.configuracion.id;


--
-- Name: connections; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.connections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    url_path text,
    user_id uuid,
    name text NOT NULL,
    db_name text NOT NULL,
    db_host text DEFAULT 'localhost'::text NOT NULL,
    db_port integer DEFAULT 5432 NOT NULL,
    db_user text DEFAULT ''::text NOT NULL,
    db_pass text DEFAULT ''::text,
    db_connection_timeout integer,
    db_schema_filter jsonb,
    db_ssl text DEFAULT 'disable'::text NOT NULL,
    ssl_certificate text,
    ssl_client_certificate text,
    ssl_client_certificate_key text,
    ssl_reject_unauthorized boolean,
    db_conn text DEFAULT ''::text,
    db_watch_shema boolean DEFAULT true,
    disable_realtime boolean DEFAULT false,
    prgl_url text,
    prgl_params jsonb,
    type text NOT NULL,
    is_state_db boolean,
    on_mount_ts text,
    on_mount_ts_disabled boolean,
    info jsonb,
    table_options jsonb,
    config jsonb,
    created timestamp without time zone DEFAULT now(),
    last_updated bigint DEFAULT 0 NOT NULL,
    CONSTRAINT "Check connection type" CHECK (((type = ANY (ARRAY['Standard'::text, 'Connection URI'::text, 'Prostgles'::text])) AND ((type <> 'Connection URI'::text) OR (length(db_conn) > 1)) AND ((type <> 'Standard'::text) OR (length(db_host) > 1)) AND ((type <> 'Prostgles'::text) OR (length(prgl_url) > 0)))),
    CONSTRAINT connections_config_check CHECK (public.validate_jsonb_schema('{"nullable":true,"type":{"enabled":"boolean","path":"string"}}'::text, config, '{"table": "connections", "column": "config"}'::jsonb)),
    CONSTRAINT connections_db_connection_timeout_check CHECK ((db_connection_timeout > 0)),
    CONSTRAINT connections_db_name_check CHECK ((length(db_name) > 0)),
    CONSTRAINT connections_db_schema_filter_check CHECK (public.validate_jsonb_schema('{"nullable":true,"oneOf":[{"record":{"values":{"enum":[1]}}},{"record":{"values":{"enum":[0]}}}]}'::text, db_schema_filter, '{"table": "connections", "column": "db_schema_filter"}'::jsonb)),
    CONSTRAINT connections_db_ssl_check CHECK (((db_ssl = 'disable'::text) OR (db_ssl = 'allow'::text) OR (db_ssl = 'prefer'::text) OR (db_ssl = 'require'::text) OR (db_ssl = 'verify-ca'::text) OR (db_ssl = 'verify-full'::text))),
    CONSTRAINT connections_info_check CHECK (public.validate_jsonb_schema('{"nullable":true,"type":{"canCreateDb":{"type":"boolean","optional":true,"description":"True if postgres user is allowed to create databases. Never gets updated"}}}'::text, info, '{"table": "connections", "column": "info"}'::jsonb)),
    CONSTRAINT connections_name_check CHECK ((length(name) > 0)),
    CONSTRAINT connections_table_options_check CHECK (public.validate_jsonb_schema('{"nullable":true,"record":{"partial":true,"values":{"type":{"icon":{"type":"string","optional":true}}}}}'::text, table_options, '{"table": "connections", "column": "table_options"}'::jsonb)),
    CONSTRAINT connections_type_check CHECK (((type = 'Standard'::text) OR (type = 'Connection URI'::text) OR (type = 'Prostgles'::text))),
    CONSTRAINT connections_url_path_check CHECK (((length(url_path) > 0) AND (url_path ~ '^[a-z0-9-]+$'::text)))
);


ALTER TABLE public.connections OWNER TO postgres;

--
-- Name: consultas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.consultas (
    id integer NOT NULL,
    usuario character varying(50) NOT NULL,
    codigo_barras character varying(50) NOT NULL,
    item_id integer,
    fecha_hora timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    resultado text
);


ALTER TABLE public.consultas OWNER TO postgres;

--
-- Name: consultas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.consultas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.consultas_id_seq OWNER TO postgres;

--
-- Name: consultas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.consultas_id_seq OWNED BY public.consultas.id;


--
-- Name: credential_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.credential_types (
    id text NOT NULL
);


ALTER TABLE public.credential_types OWNER TO postgres;

--
-- Name: credentials; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.credentials (
    id integer NOT NULL,
    name text DEFAULT ''::text NOT NULL,
    user_id uuid,
    type text DEFAULT 's3'::text NOT NULL,
    key_id text NOT NULL,
    key_secret text NOT NULL,
    bucket text,
    region text,
    CONSTRAINT "Bucket or Region missing" CHECK (((type <> 's3'::text) OR ((bucket IS NOT NULL) AND (region IS NOT NULL))))
);


ALTER TABLE public.credentials OWNER TO postgres;

--
-- Name: credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.credentials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.credentials_id_seq OWNER TO postgres;

--
-- Name: credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.credentials_id_seq OWNED BY public.credentials.id;


--
-- Name: database_config_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.database_config_logs (
    id integer NOT NULL,
    on_mount_logs text,
    table_config_logs text,
    on_run_logs text
);


ALTER TABLE public.database_config_logs OWNER TO postgres;

--
-- Name: database_config_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.database_config_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.database_config_logs_id_seq OWNER TO postgres;

--
-- Name: database_config_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.database_config_logs_id_seq OWNED BY public.database_config_logs.id;


--
-- Name: database_configs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.database_configs (
    id integer NOT NULL,
    db_name text NOT NULL,
    db_host text NOT NULL,
    db_port integer NOT NULL,
    rest_api_enabled boolean DEFAULT false,
    sync_users boolean DEFAULT false,
    table_config jsonb,
    table_config_ts text,
    table_config_ts_disabled boolean,
    file_table_config jsonb,
    backups_config jsonb,
    CONSTRAINT database_configs_backups_config_check CHECK (public.validate_jsonb_schema('{"nullable":true,"info":{"hint":"Automatic backups configurations"},"type":{"enabled":{"type":"boolean","optional":true},"cloudConfig":{"nullable":true,"type":{"credential_id":{"type":"number","nullable":true,"optional":true}}},"frequency":{"enum":["daily","monthly","weekly","hourly"]},"hour":{"type":"integer","optional":true},"dayOfWeek":{"type":"integer","optional":true},"dayOfMonth":{"type":"integer","optional":true},"keepLast":{"type":"integer","optional":true},"err":{"type":"string","optional":true,"nullable":true},"dump_options":{"oneOfType":[{"command":{"enum":["pg_dumpall"]},"clean":{"type":"boolean"},"dataOnly":{"type":"boolean","optional":true},"globalsOnly":{"type":"boolean","optional":true},"rolesOnly":{"type":"boolean","optional":true},"schemaOnly":{"type":"boolean","optional":true},"ifExists":{"type":"boolean","optional":true},"encoding":{"type":"string","optional":true},"keepLogs":{"type":"boolean","optional":true}},{"command":{"enum":["pg_dump"]},"format":{"enum":["p","t","c"]},"dataOnly":{"type":"boolean","optional":true},"clean":{"type":"boolean","optional":true},"create":{"type":"boolean","optional":true},"encoding":{"type":"string","optional":true},"numberOfJobs":{"type":"integer","optional":true},"noOwner":{"type":"boolean","optional":true},"compressionLevel":{"type":"integer","optional":true},"ifExists":{"type":"boolean","optional":true},"keepLogs":{"type":"boolean","optional":true},"excludeSchema":{"type":"string","optional":true},"schemaOnly":{"type":"boolean","optional":true}}]}}}'::text, backups_config, '{"table": "database_configs", "column": "backups_config"}'::jsonb)),
    CONSTRAINT database_configs_file_table_config_check CHECK (public.validate_jsonb_schema('{"nullable":true,"info":{"hint":"File storage configurations"},"type":{"fileTable":{"type":"string","optional":true},"storageType":{"oneOfType":[{"type":{"enum":["local"]}},{"type":{"enum":["S3"]},"credential_id":{"type":"number"}}]},"referencedTables":{"type":"any","optional":true},"delayedDelete":{"optional":true,"type":{"deleteAfterNDays":{"type":"number"},"checkIntervalHours":{"type":"number","optional":true}}}}}'::text, file_table_config, '{"table": "database_configs", "column": "file_table_config"}'::jsonb)),
    CONSTRAINT database_configs_table_config_check CHECK (public.validate_jsonb_schema('{"nullable":true,"info":{"hint":"Table configurations"},"record":{"values":{"oneOfType":[{"isLookupTable":{"type":{"values":{"record":{"values":{"type":"string","optional":true}}}}}},{"columns":{"description":"Column definitions and hints","record":{"values":{"oneOf":["string",{"type":{"hint":{"type":"string","optional":true},"nullable":{"type":"boolean","optional":true},"isText":{"type":"boolean","optional":true},"trimmed":{"type":"boolean","optional":true},"defaultValue":{"type":"any","optional":true}}},{"type":{"jsonbSchema":{"oneOfType":[{"type":{"enum":["string","number","boolean","Date","time","timestamp","string[]","number[]","boolean[]","Date[]","time[]","timestamp[]"]},"optional":{"type":"boolean","optional":true},"description":{"type":"string","optional":true}},{"type":{"enum":["Lookup","Lookup[]"]},"optional":{"type":"boolean","optional":true},"description":{"type":"string","optional":true}},{"type":{"enum":["object"]},"optional":{"type":"boolean","optional":true},"description":{"type":"string","optional":true}}]}}}]}}}}]}}}'::text, table_config, '{"table": "database_configs", "column": "table_config"}'::jsonb))
);


ALTER TABLE public.database_configs OWNER TO postgres;

--
-- Name: database_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.database_configs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.database_configs_id_seq OWNER TO postgres;

--
-- Name: database_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.database_configs_id_seq OWNED BY public.database_configs.id;


--
-- Name: database_stats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.database_stats (
    database_config_id integer
);


ALTER TABLE public.database_stats OWNER TO postgres;

--
-- Name: global_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.global_settings (
    id integer NOT NULL,
    allowed_origin text,
    allowed_ips cidr[] DEFAULT '{}'::cidr[] NOT NULL,
    allowed_ips_enabled boolean DEFAULT false NOT NULL,
    trust_proxy boolean DEFAULT false NOT NULL,
    enable_logs boolean DEFAULT false NOT NULL,
    session_max_age_days integer DEFAULT 14 NOT NULL,
    magic_link_validity_days integer DEFAULT 1 NOT NULL,
    updated_by text DEFAULT 'app'::text NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    pass_process_env_vars_to_server_side_functions boolean DEFAULT false NOT NULL,
    login_rate_limit_enabled boolean DEFAULT true NOT NULL,
    login_rate_limit jsonb DEFAULT '{"groupBy": "ip", "maxAttemptsPerHour": 5}'::jsonb NOT NULL,
    auth_providers jsonb,
    "tableConfig" jsonb,
    prostgles_registration jsonb,
    CONSTRAINT global_settings_auth_providers_check CHECK (public.validate_jsonb_schema('{"nullable":true,"info":{"hint":"The provided credentials will allow users to register and sign in. The redirect uri format is {website_url}/auth/{providerName}/callback"},"type":{"website_url":{"type":"string","title":"Website URL"},"created_user_type":{"type":"string","optional":true,"title":"User type assigned to new users. Defaults to ''default''"},"email":{"optional":true,"oneOfType":[{"signupType":{"enum":["withMagicLink"]},"enabled":{"type":"boolean","optional":true},"smtp":{"oneOfType":[{"type":{"enum":["smtp"]},"host":{"type":"string"},"port":{"type":"number"},"secure":{"type":"boolean","optional":true},"rejectUnauthorized":{"type":"boolean","optional":true},"user":{"type":"string"},"pass":{"type":"string"}},{"type":{"enum":["aws-ses"]},"region":{"type":"string"},"accessKeyId":{"type":"string"},"secretAccessKey":{"type":"string"},"sendingRate":{"type":"integer","optional":true}}]},"emailTemplate":{"title":"Email template used for sending auth emails. Must contain placeholders for the url: ${url}","type":{"from":"string","subject":"string","body":"string"}},"emailConfirmationEnabled":{"type":"boolean","optional":true,"title":"Enable email confirmation"}},{"signupType":{"enum":["withPassword"]},"enabled":{"type":"boolean","optional":true},"minPasswordLength":{"optional":true,"type":"integer","title":"Minimum password length"},"smtp":{"oneOfType":[{"type":{"enum":["smtp"]},"host":{"type":"string"},"port":{"type":"number"},"secure":{"type":"boolean","optional":true},"rejectUnauthorized":{"type":"boolean","optional":true},"user":{"type":"string"},"pass":{"type":"string"}},{"type":{"enum":["aws-ses"]},"region":{"type":"string"},"accessKeyId":{"type":"string"},"secretAccessKey":{"type":"string"},"sendingRate":{"type":"integer","optional":true}}]},"emailTemplate":{"title":"Email template used for sending auth emails. Must contain placeholders for the url: ${url}","type":{"from":"string","subject":"string","body":"string"}},"emailConfirmationEnabled":{"type":"boolean","optional":true,"title":"Enable email confirmation"}}]},"google":{"optional":true,"type":{"enabled":{"type":"boolean","optional":true},"clientID":{"type":"string"},"clientSecret":{"type":"string"},"authOpts":{"optional":true,"type":{"scope":{"type":"string[]","allowedValues":["profile","email","calendar","calendar.readonly","calendar.events","calendar.events.readonly"]}}}}},"github":{"optional":true,"type":{"enabled":{"type":"boolean","optional":true},"clientID":{"type":"string"},"clientSecret":{"type":"string"},"authOpts":{"optional":true,"type":{"scope":{"type":"string[]","allowedValues":["read:user","user:email"]}}}}},"microsoft":{"optional":true,"type":{"enabled":{"type":"boolean","optional":true},"clientID":{"type":"string"},"clientSecret":{"type":"string"},"authOpts":{"optional":true,"type":{"prompt":{"enum":["login","none","consent","select_account","create"]},"scope":{"type":"string[]","allowedValues":["openid","profile","email","offline_access","User.Read","User.ReadBasic.All","User.Read.All"]}}}}},"facebook":{"optional":true,"type":{"enabled":{"type":"boolean","optional":true},"clientID":{"type":"string"},"clientSecret":{"type":"string"},"authOpts":{"optional":true,"type":{"scope":{"type":"string[]","allowedValues":["email","public_profile","user_birthday","user_friends","user_gender","user_hometown"]}}}}},"customOAuth":{"optional":true,"type":{"enabled":{"type":"boolean","optional":true},"clientID":{"type":"string"},"clientSecret":{"type":"string"},"displayName":{"type":"string"},"displayIconPath":{"type":"string","optional":true},"authorizationURL":{"type":"string"},"tokenURL":{"type":"string"},"authOpts":{"optional":true,"type":{"scope":{"type":"string[]"}}}}}}}'::text, auth_providers, '{"table": "global_settings", "column": "auth_providers"}'::jsonb)),
    CONSTRAINT global_settings_check CHECK (((allowed_ips_enabled = false) OR (cardinality(allowed_ips) > 0))),
    CONSTRAINT global_settings_login_rate_limit_check CHECK (public.validate_jsonb_schema('{"info":{"hint":"List of allowed IP addresses in ipv4 or ipv6 format"},"type":{"maxAttemptsPerHour":{"type":"integer","description":"Maximum number of login attempts allowed per hour"},"groupBy":{"description":"The IP address used to group login attempts","enum":["x-real-ip","remote_ip","ip"]}}}'::text, login_rate_limit, '{"table": "global_settings", "column": "login_rate_limit"}'::jsonb)),
    CONSTRAINT global_settings_magic_link_validity_days_check CHECK ((magic_link_validity_days > 0)),
    CONSTRAINT global_settings_prostgles_registration_check CHECK (public.validate_jsonb_schema('{"nullable":true,"info":{"hint":"Registration options"},"type":{"enabled":{"type":"boolean"},"email":{"type":"string"},"token":{"type":"string"}}}'::text, prostgles_registration, '{"table": "global_settings", "column": "prostgles_registration"}'::jsonb)),
    CONSTRAINT global_settings_session_max_age_days_check CHECK ((session_max_age_days > 0)),
    CONSTRAINT global_settings_updated_by_check CHECK (((updated_by = 'user'::text) OR (updated_by = 'app'::text)))
);


ALTER TABLE public.global_settings OWNER TO postgres;

--
-- Name: global_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.global_settings ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.global_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: historico_capturas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.historico_capturas (
    id integer NOT NULL,
    codigo_barras character varying(100) NOT NULL,
    item_code character varying(50) NOT NULL,
    resultado text,
    motivo character varying(100),
    cumple character varying(20),
    usuario character varying(50) NOT NULL,
    fecha_captura timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    procesado boolean DEFAULT false
);


ALTER TABLE public.historico_capturas OWNER TO postgres;

--
-- Name: historico_capturas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.historico_capturas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.historico_capturas_id_seq OWNER TO postgres;

--
-- Name: historico_capturas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.historico_capturas_id_seq OWNED BY public.historico_capturas.id;


--
-- Name: items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.items (
    id integer NOT NULL,
    item character varying(20) NOT NULL,
    resultado text,
    fecha_actualizacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.items OWNER TO postgres;

--
-- Name: items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.items_id_seq OWNER TO postgres;

--
-- Name: items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.items_id_seq OWNED BY public.items.id;


--
-- Name: links; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.links (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    w1_id uuid NOT NULL,
    w2_id uuid NOT NULL,
    workspace_id uuid,
    disabled boolean,
    options jsonb NOT NULL,
    closed boolean DEFAULT false,
    deleted boolean DEFAULT false,
    created timestamp without time zone DEFAULT now(),
    last_updated bigint NOT NULL,
    CONSTRAINT links_options_check CHECK (public.validate_jsonb_schema('{"oneOfType":[{"type":{"enum":["table"]},"colorArr":{"type":"number[]","optional":true},"tablePath":{"description":"Table path from w1.table_name to w2.table_name","arrayOfType":{"table":"string","on":{"arrayOf":{"record":{"values":"any"}}}},"optional":false}},{"type":{"enum":["map"]},"dataSource":{"optional":true,"oneOfType":[{"type":{"enum":["sql"],"description":"Show data from an SQL query within an editor. Will not reflect latest changes to that query (must be re-added)"},"sql":"string","withStatement":"string"},{"type":{"enum":["table"],"description":"Shows data from an opened table window. Any filters from that table will apply to the chart as well"},"joinPath":{"description":"When adding a chart this allows showing data from a table that joins to the current table","arrayOfType":{"table":"string","on":{"arrayOf":{"record":{"values":"any"}}}},"optional":true}},{"type":{"enum":["local-table"],"description":"Shows data from postgres table not connected to any window (w1_id === w2_id === current chart window). Custom filters can be added"},"localTableName":{"type":"string"},"smartGroupFilter":{"oneOfType":[{"$and":"any[]"},{"$or":"any[]"}],"optional":true}}]},"smartGroupFilter":{"oneOfType":[{"$and":"any[]"},{"$or":"any[]"}],"optional":true},"joinPath":{"description":"When adding a chart this allows showing data from a table that joins to the current table","arrayOfType":{"table":"string","on":{"arrayOf":{"record":{"values":"any"}}}},"optional":true},"localTableName":{"type":"string","optional":true,"description":"If provided then this is a local layer (w1_id === w2_id === current chart window)"},"sql":{"description":"Defined if chart links to SQL statement","optional":true,"type":"string"},"osmLayerQuery":{"type":"string","optional":true,"description":"If provided then this is a OSM layer (w1_id === w2_id === current chart window)"},"mapIcons":{"optional":true,"oneOfType":[{"type":{"enum":["fixed"]},"iconPath":"string"},{"type":{"enum":["conditional"]},"columnName":"string","conditions":{"arrayOfType":{"value":"any","iconPath":"string"}}}]},"mapColorMode":{"optional":true,"oneOfType":[{"type":{"enum":["fixed"]},"colorArr":"number[]"},{"type":{"enum":["scale"]},"columnName":"string","min":"number","max":"number","minColorArr":"number[]","maxColorArr":"number[]"},{"type":{"enum":["conditional"]},"columnName":"string","conditions":{"arrayOfType":{"value":"any","colorArr":"number[]"}}}]},"mapShowText":{"optional":true,"type":{"columnName":{"type":"string"}}},"columns":{"arrayOfType":{"name":{"type":"string","description":"Geometry/Geography column"},"colorArr":"number[]"}}},{"type":{"enum":["timechart"]},"dataSource":{"optional":true,"oneOfType":[{"type":{"enum":["sql"],"description":"Show data from an SQL query within an editor. Will not reflect latest changes to that query (must be re-added)"},"sql":"string","withStatement":"string"},{"type":{"enum":["table"],"description":"Shows data from an opened table window. Any filters from that table will apply to the chart as well"},"joinPath":{"description":"When adding a chart this allows showing data from a table that joins to the current table","arrayOfType":{"table":"string","on":{"arrayOf":{"record":{"values":"any"}}}},"optional":true}},{"type":{"enum":["local-table"],"description":"Shows data from postgres table not connected to any window (w1_id === w2_id === current chart window). Custom filters can be added"},"localTableName":{"type":"string"},"smartGroupFilter":{"oneOfType":[{"$and":"any[]"},{"$or":"any[]"}],"optional":true}}]},"smartGroupFilter":{"oneOfType":[{"$and":"any[]"},{"$or":"any[]"}],"optional":true},"joinPath":{"description":"When adding a chart this allows showing data from a table that joins to the current table","arrayOfType":{"table":"string","on":{"arrayOf":{"record":{"values":"any"}}}},"optional":true},"localTableName":{"type":"string","optional":true,"description":"If provided then this is a local layer (w1_id === w2_id === current chart window)"},"sql":{"description":"Defined if chart links to SQL statement","optional":true,"type":"string"},"groupByColumn":{"type":"string","optional":true,"description":"Used by timechart"},"otherColumns":{"arrayOfType":{"name":"string","label":{"type":"string","optional":true},"udt_name":"string"},"optional":true},"columns":{"arrayOfType":{"name":{"type":"string","description":"Date column"},"colorArr":"number[]","statType":{"optional":true,"type":{"funcName":{"enum":["$min","$max","$countAll","$avg","$sum"]},"numericColumn":"string"}}}}}]}'::text, options, '{"table": "links", "column": "options"}'::jsonb))
);


ALTER TABLE public.links OWNER TO postgres;

--
-- Name: llm_chats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.llm_chats (
    id integer NOT NULL,
    name text DEFAULT 'New chat'::text NOT NULL,
    user_id uuid NOT NULL,
    llm_credential_id integer,
    llm_prompt_id integer,
    created timestamp without time zone DEFAULT now(),
    disabled_message text,
    disabled_until timestamp with time zone
);


ALTER TABLE public.llm_chats OWNER TO postgres;

--
-- Name: llm_chats_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.llm_chats ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.llm_chats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: llm_credentials; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.llm_credentials (
    id integer NOT NULL,
    name text DEFAULT 'Default credential'::text NOT NULL,
    user_id uuid NOT NULL,
    endpoint text DEFAULT 'https://api.openai.com/v1/chat/completions'::text NOT NULL,
    config jsonb DEFAULT '{"model": "gpt-4o", "API_Key": "", "Provider": "OpenAI"}'::jsonb NOT NULL,
    is_default boolean DEFAULT false,
    result_path text[],
    created timestamp without time zone DEFAULT now(),
    CONSTRAINT llm_credentials_config_check CHECK (public.validate_jsonb_schema('{"oneOfType":[{"Provider":{"enum":["OpenAI"]},"API_Key":{"type":"string"},"model":{"type":"string"},"temperature":{"type":"number","optional":true},"frequency_penalty":{"type":"number","optional":true},"max_completion_tokens":{"type":"integer","optional":true},"presence_penalty":{"type":"number","optional":true},"response_format":{"enum":["json","text","srt","verbose_json","vtt"],"optional":true}},{"Provider":{"enum":["Anthropic"]},"API_Key":{"type":"string"},"anthropic-version":{"type":"string"},"model":{"type":"string"},"max_tokens":{"type":"integer"}},{"Provider":{"enum":["Custom"]},"headers":{"record":{"values":"string"},"optional":true},"body":{"record":{"values":"string"},"optional":true}},{"Provider":{"enum":["Prostgles"]},"API_Key":{"type":"string"}}]}'::text, config, '{"table": "llm_credentials", "column": "config"}'::jsonb))
);


ALTER TABLE public.llm_credentials OWNER TO postgres;

--
-- Name: llm_credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.llm_credentials ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.llm_credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: llm_messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.llm_messages (
    id bigint NOT NULL,
    chat_id integer NOT NULL,
    user_id uuid,
    message text NOT NULL,
    created timestamp without time zone DEFAULT now()
);


ALTER TABLE public.llm_messages OWNER TO postgres;

--
-- Name: llm_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.llm_messages ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.llm_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: llm_prompts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.llm_prompts (
    id integer NOT NULL,
    name text DEFAULT 'New prompt'::text NOT NULL,
    description text DEFAULT ''::text,
    user_id uuid,
    prompt text NOT NULL,
    created timestamp without time zone DEFAULT now(),
    CONSTRAINT llm_prompts_prompt_check CHECK ((length(btrim(prompt)) > 0))
);


ALTER TABLE public.llm_prompts OWNER TO postgres;

--
-- Name: llm_prompts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.llm_prompts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.llm_prompts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: login_attempts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.login_attempts (
    id bigint NOT NULL,
    type text DEFAULT 'web'::text NOT NULL,
    auth_type text NOT NULL,
    username text,
    created timestamp without time zone DEFAULT now(),
    failed boolean,
    magic_link_id text,
    sid text,
    auth_provider text,
    ip_address inet NOT NULL,
    ip_address_remote text NOT NULL,
    x_real_ip text NOT NULL,
    user_agent text NOT NULL,
    info text,
    CONSTRAINT login_attempts_auth_type_check CHECK (((auth_type = 'session-id'::text) OR (auth_type = 'registration'::text) OR (auth_type = 'email-confirmation'::text) OR (auth_type = 'magic-link-registration'::text) OR (auth_type = 'magic-link'::text) OR (auth_type = 'otp-code'::text) OR (auth_type = 'login'::text) OR (auth_type = 'oauth'::text))),
    CONSTRAINT login_attempts_check CHECK (((auth_type <> 'oauth'::text) OR (auth_provider IS NOT NULL))),
    CONSTRAINT login_attempts_type_check CHECK (((type = 'web'::text) OR (type = 'api_token'::text) OR (type = 'mobile'::text)))
);


ALTER TABLE public.login_attempts OWNER TO postgres;

--
-- Name: login_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.login_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.login_attempts_id_seq OWNER TO postgres;

--
-- Name: login_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.login_attempts_id_seq OWNED BY public.login_attempts.id;


--
-- Name: logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.logs (
    id bigint NOT NULL,
    connection_id uuid,
    type text,
    command text,
    table_name text,
    sid text,
    tx_info jsonb,
    socket_id text,
    duration numeric,
    data jsonb,
    error json,
    has_error boolean,
    created timestamp without time zone DEFAULT now()
);


ALTER TABLE public.logs OWNER TO postgres;

--
-- Name: logs_aplicacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.logs_aplicacion (
    id integer NOT NULL,
    nivel character varying(20) NOT NULL,
    mensaje text NOT NULL,
    usuario character varying(50),
    fecha timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.logs_aplicacion OWNER TO postgres;

--
-- Name: logs_aplicacion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.logs_aplicacion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.logs_aplicacion_id_seq OWNER TO postgres;

--
-- Name: logs_aplicacion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.logs_aplicacion_id_seq OWNED BY public.logs_aplicacion.id;


--
-- Name: logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.logs_id_seq OWNER TO postgres;

--
-- Name: logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.logs_id_seq OWNED BY public.logs.id;


--
-- Name: magic_links; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.magic_links (
    id text DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    magic_link text,
    magic_link_used timestamp without time zone,
    expires bigint NOT NULL,
    session_expires bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.magic_links OWNER TO postgres;

--
-- Name: published_methods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.published_methods (
    id integer NOT NULL,
    name text DEFAULT 'Method name'::text NOT NULL,
    description text DEFAULT 'Method description'::text NOT NULL,
    connection_id uuid,
    arguments jsonb DEFAULT '[]'::jsonb NOT NULL,
    run text DEFAULT 'export const run: ProstglesMethod = async (args, { db, dbo, user }) => {
  
}'::text NOT NULL,
    "outputTable" text,
    CONSTRAINT published_methods_arguments_check CHECK (public.validate_jsonb_schema('{"nullable":false,"title":"Arguments","arrayOf":{"oneOfType":[{"name":{"title":"Argument name","type":"string"},"type":{"title":"Data type","enum":["any","string","number","boolean","Date","time","timestamp","string[]","number[]","boolean[]","Date[]","time[]","timestamp[]"]},"defaultValue":{"type":"string","optional":true},"optional":{"optional":true,"type":"boolean","title":"Optional"},"allowedValues":{"title":"Allowed values","optional":true,"type":"string[]"}},{"name":{"title":"Argument name","type":"string"},"type":{"title":"Data type","enum":["Lookup","Lookup[]"]},"defaultValue":{"type":"any","optional":true},"optional":{"optional":true,"type":"boolean"},"lookup":{"title":"Table column","lookup":{"type":"data-def","column":"","table":""}}},{"name":{"title":"Argument name","type":"string"},"type":{"title":"Data type","enum":["JsonbSchema"]},"defaultValue":{"type":"any","optional":true},"optional":{"optional":true,"type":"boolean"},"schema":{"title":"Jsonb schema","oneOfType":[{"type":{"enum":["boolean","number","integer","string","Date","time","timestamp","any","boolean[]","number[]","integer[]","string[]","Date[]","time[]","timestamp[]","any[]"]},"optional":{"type":"boolean","optional":true},"nullable":{"type":"boolean","optional":true},"description":{"type":"string","optional":true},"title":{"type":"string","optional":true},"defaultValue":{"type":"any","optional":true}},{"type":{"enum":["object","object[]"]},"optional":{"type":"boolean","optional":true},"nullable":{"type":"boolean","optional":true},"description":{"type":"string","optional":true},"title":{"type":"string","optional":true},"defaultValue":{"type":"any","optional":true},"properties":{"record":{"values":{"type":{"type":{"enum":["boolean","number","integer","string","Date","time","timestamp","any","boolean[]","number[]","integer[]","string[]","Date[]","time[]","timestamp[]","any[]"]},"optional":{"type":"boolean","optional":true},"nullable":{"type":"boolean","optional":true},"description":{"type":"string","optional":true},"title":{"type":"string","optional":true},"defaultValue":{"type":"any","optional":true}}}}}}]}}]}}'::text, arguments, '{"table": "published_methods", "column": "arguments"}'::jsonb))
);


ALTER TABLE public.published_methods OWNER TO postgres;

--
-- Name: published_methods_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.published_methods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.published_methods_id_seq OWNER TO postgres;

--
-- Name: published_methods_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.published_methods_id_seq OWNED BY public.published_methods.id;


--
-- Name: schema_version; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schema_version (
    id numeric NOT NULL,
    table_config jsonb NOT NULL
);


ALTER TABLE public.schema_version OWNER TO postgres;

--
-- Name: session_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.session_types (
    id text NOT NULL
);


ALTER TABLE public.session_types OWNER TO postgres;

--
-- Name: sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sessions (
    id text NOT NULL,
    id_num integer NOT NULL,
    user_id uuid NOT NULL,
    name text,
    socket_id text,
    user_type text NOT NULL,
    is_mobile boolean DEFAULT false,
    is_connected boolean DEFAULT false,
    active boolean DEFAULT true,
    project_id text,
    ip_address inet NOT NULL,
    type text NOT NULL,
    user_agent text,
    created timestamp without time zone DEFAULT now(),
    last_used timestamp without time zone DEFAULT now(),
    expires bigint NOT NULL
);


ALTER TABLE public.sessions OWNER TO postgres;

--
-- Name: sessions_id_num_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.sessions_id_num_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sessions_id_num_seq OWNER TO postgres;

--
-- Name: sessions_id_num_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.sessions_id_num_seq OWNED BY public.sessions.id_num;


--
-- Name: stats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stats (
    connection_id uuid NOT NULL,
    datid integer,
    datname text,
    pid integer NOT NULL,
    usesysid integer,
    usename text,
    application_name text,
    client_addr text,
    client_hostname text,
    client_port integer,
    backend_start text,
    xact_start text,
    query_start timestamp without time zone,
    state_change text,
    wait_event_type text,
    wait_event text,
    state text,
    backend_xid text,
    backend_xmin text,
    query text,
    backend_type text,
    blocked_by integer[],
    blocked_by_num integer DEFAULT 0 NOT NULL,
    id_query_hash text,
    cpu numeric,
    mem numeric,
    "memPretty" text,
    mhz text,
    cmd text
);


ALTER TABLE public.stats OWNER TO postgres;

--
-- Name: user_statuses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_statuses (
    id text NOT NULL
);


ALTER TABLE public.user_statuses OWNER TO postgres;

--
-- Name: user_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_types (
    id text NOT NULL,
    en text
);


ALTER TABLE public.user_types OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    username text NOT NULL,
    name text,
    email text,
    registration jsonb,
    auth_provider text,
    auth_provider_user_id text,
    auth_provider_profile jsonb,
    password text NOT NULL,
    type text DEFAULT 'default'::text NOT NULL,
    passwordless_admin boolean,
    created timestamp without time zone DEFAULT now(),
    last_updated bigint DEFAULT (EXTRACT(epoch FROM now()) * (1000)::numeric),
    options jsonb,
    "2fa" jsonb,
    has_2fa_enabled boolean GENERATED ALWAYS AS ((("2fa" ->> 'enabled'::text))::boolean) STORED,
    CONSTRAINT "passwordless_admin type AND username CHECK" CHECK (((COALESCE(passwordless_admin, false) = false) OR ((type = 'admin'::text) AND (username = 'passwordless_admin'::text)))),
    CONSTRAINT users_2fa_check CHECK (public.validate_jsonb_schema('{"nullable":true,"type":{"secret":{"type":"string"},"recoveryCode":{"type":"string"},"enabled":{"type":"boolean"}}}'::text, "2fa", '{"table": "users", "column": "2fa"}'::jsonb)),
    CONSTRAINT users_options_check CHECK (public.validate_jsonb_schema('{"nullable":true,"type":{"showStateDB":{"type":"boolean","optional":true,"description":"Show the prostgles database in the connections list"},"hideNonSSLWarning":{"type":"boolean","optional":true,"description":"Hides the top warning when accessing the website over an insecure connection (non-HTTPS)"},"viewedSQLTips":{"type":"boolean","optional":true,"description":"Will hide SQL tips if true"},"viewedAccessInfo":{"type":"boolean","optional":true,"description":"Will hide passwordless user tips if true"},"theme":{"enum":["dark","light","from-system"],"optional":true}}}'::text, options, '{"table": "users", "column": "options"}'::jsonb)),
    CONSTRAINT users_registration_check CHECK (public.validate_jsonb_schema('{"nullable":true,"oneOfType":[{"type":{"enum":["password-w-email-confirmation"]},"email_confirmation":{"oneOfType":[{"status":{"enum":["confirmed"]},"date":"Date"},{"status":{"enum":["pending"]},"confirmation_code":{"type":"string"},"date":"Date"}]}},{"type":{"enum":["magic-link"]},"otp_code":{"type":"string"},"date":"Date","used_on":{"type":"Date","optional":true}},{"type":{"enum":["OAuth"]},"provider":{"enum":["google","facebook","github","microsoft","customOAuth"],"description":"OAuth provider name. E.g.: google, github"},"user_id":"string","profile":"any"}]}'::text, registration, '{"table": "users", "column": "registration"}'::jsonb)),
    CONSTRAINT users_username_check CHECK ((length(username) > 0))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: usuarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuarios (
    id integer NOT NULL,
    usuario character varying(50) NOT NULL,
    "contrase├▒a" character varying(100) NOT NULL,
    rol character varying(20) DEFAULT 'usuario'::character varying NOT NULL,
    fecha_creacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    activo boolean DEFAULT true,
    ultimo_acceso timestamp without time zone
);


ALTER TABLE public.usuarios OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuarios_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.usuarios_id_seq OWNER TO postgres;

--
-- Name: usuarios_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuarios_id_seq OWNED BY public.usuarios.id;


--
-- Name: versiones; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.versiones (
    id integer NOT NULL,
    version character varying(20) NOT NULL,
    fecha_lanzamiento timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    descripcion text,
    url_descarga text,
    obligatoria boolean DEFAULT false,
    activa boolean DEFAULT true
);


ALTER TABLE public.versiones OWNER TO postgres;

--
-- Name: versiones_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.versiones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.versiones_id_seq OWNER TO postgres;

--
-- Name: versiones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.versiones_id_seq OWNED BY public.versiones.id;


--
-- Name: windows; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.windows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    parent_window_id uuid,
    user_id uuid NOT NULL,
    workspace_id uuid,
    type text,
    table_name text,
    method_name text,
    table_oid integer,
    sql text DEFAULT ''::text NOT NULL,
    selected_sql text DEFAULT ''::text NOT NULL,
    name text,
    "limit" integer DEFAULT 1000,
    closed boolean DEFAULT false,
    deleted boolean DEFAULT false,
    show_menu boolean DEFAULT false,
    minimised boolean DEFAULT false,
    fullscreen boolean DEFAULT true,
    sort jsonb DEFAULT '[]'::jsonb,
    filter jsonb DEFAULT '[]'::jsonb NOT NULL,
    "having" jsonb DEFAULT '[]'::jsonb NOT NULL,
    options jsonb DEFAULT '{}'::jsonb NOT NULL,
    function_options jsonb,
    sql_options jsonb DEFAULT '{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}'::jsonb NOT NULL,
    columns jsonb,
    nested_tables jsonb,
    created timestamp without time zone DEFAULT now() NOT NULL,
    last_updated bigint NOT NULL,
    CONSTRAINT windows_check CHECK ((NOT ((type = 'sql'::text) AND (deleted = true) AND (((options ->> 'sqlWasSaved'::text))::boolean = true)))),
    CONSTRAINT windows_function_options_check CHECK (public.validate_jsonb_schema('{"nullable":true,"type":{"showDefinition":{"type":"boolean","optional":true,"description":"Show the function definition"}}}'::text, function_options, '{"table": "windows", "column": "function_options"}'::jsonb)),
    CONSTRAINT windows_limit_check CHECK ((("limit" > '-1'::integer) AND ("limit" < 100000))),
    CONSTRAINT windows_sql_options_check CHECK (public.validate_jsonb_schema('{"type":{"executeOptions":{"optional":true,"description":"Behaviour of execute (ALT + E). Defaults to ''block'' \nfull = run entire sql   \nblock = run code block where the cursor is","enum":["full","block","smallest-block"]},"errorMessageDisplay":{"optional":true,"description":"Error display locations. Defaults to ''both'' \ntooltip = show within tooltip only   \nbottom = show in bottom control bar only   \nboth = show in both locations","enum":["tooltip","bottom","both"]},"tabSize":{"type":"integer","optional":true},"lineNumbers":{"optional":true,"enum":["on","off"]},"renderMode":{"optional":true,"description":"Show query results in a table or a JSON","enum":["table","csv","JSON"]},"minimap":{"optional":true,"description":"Shows a vertical code minimap to the right","type":{"enabled":{"type":"boolean"}}},"acceptSuggestionOnEnter":{"description":"Insert suggestions on Enter. Tab is the default key","optional":true,"enum":["on","smart","off"]},"expandSuggestionDocs":{"optional":true,"description":"Toggle suggestions documentation tab. Requires page refresh. Enabled by default","type":"boolean"},"maxCharsPerCell":{"type":"integer","optional":true,"description":"Defaults to 1000. Maximum number of characters to display for each cell. Useful in improving performance"},"theme":{"optional":true,"enum":["vs","vs-dark","hc-black","hc-light"]},"showRunningQueryStats":{"optional":true,"description":"(Experimental) Display running query stats (CPU and Memory usage) in the bottom bar","type":"boolean"}}}'::text, sql_options, '{"table": "windows", "column": "sql_options"}'::jsonb)),
    CONSTRAINT windows_type_check CHECK ((type = ANY (ARRAY['map'::text, 'sql'::text, 'table'::text, 'timechart'::text, 'card'::text, 'method'::text])))
);


ALTER TABLE public.windows OWNER TO postgres;

--
-- Name: workspace_publish_modes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.workspace_publish_modes (
    id text NOT NULL,
    en text,
    description text
);


ALTER TABLE public.workspace_publish_modes OWNER TO postgres;

--
-- Name: workspaces; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.workspaces (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    connection_id uuid NOT NULL,
    name text DEFAULT 'default workspace'::text NOT NULL,
    created timestamp without time zone DEFAULT now(),
    active_row jsonb DEFAULT '{}'::jsonb,
    layout jsonb,
    icon text,
    options jsonb DEFAULT '{"hideCounts": false, "pinnedMenu": true, "tableListSortBy": "extraInfo", "tableListEndInfo": "size", "defaultLayoutType": "tab"}'::jsonb NOT NULL,
    last_updated bigint NOT NULL,
    last_used timestamp without time zone DEFAULT now() NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    url_path text,
    parent_workspace_id uuid,
    published boolean DEFAULT false NOT NULL,
    publish_mode text,
    CONSTRAINT workspaces_check CHECK (((parent_workspace_id IS NULL) OR (published = false))),
    CONSTRAINT workspaces_options_check CHECK (public.validate_jsonb_schema('{"type":{"hideCounts":{"optional":true,"type":"boolean"},"tableListEndInfo":{"optional":true,"enum":["none","count","size"]},"tableListSortBy":{"optional":true,"enum":["name","extraInfo"]},"showAllMyQueries":{"optional":true,"type":"boolean"},"defaultLayoutType":{"optional":true,"enum":["row","tab","col"]},"pinnedMenu":{"optional":true,"type":"boolean"},"pinnedMenuWidth":{"optional":true,"type":"number"}}}'::text, options, '{"table": "workspaces", "column": "options"}'::jsonb))
);


ALTER TABLE public.workspaces OWNER TO postgres;

--
-- Name: access_control id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control ALTER COLUMN id SET DEFAULT nextval('public.access_control_id_seq'::regclass);


--
-- Name: alert_viewed_by id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alert_viewed_by ALTER COLUMN id SET DEFAULT nextval('public.alert_viewed_by_id_seq'::regclass);


--
-- Name: alerts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts ALTER COLUMN id SET DEFAULT nextval('public.alerts_id_seq'::regclass);


--
-- Name: capturas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.capturas ALTER COLUMN id SET DEFAULT nextval('public.capturas_id_seq'::regclass);


--
-- Name: clp_carga_detalle id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clp_carga_detalle ALTER COLUMN id SET DEFAULT nextval('public.clp_carga_detalle_id_seq'::regclass);


--
-- Name: clp_cargas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clp_cargas ALTER COLUMN id SET DEFAULT nextval('public.clp_cargas_id_seq'::regclass);


--
-- Name: codigos_barras id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_barras ALTER COLUMN id SET DEFAULT nextval('public.codigos_barras_id_seq'::regclass);


--
-- Name: codigos_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_items ALTER COLUMN id SET DEFAULT nextval('public.codigos_items_id_seq'::regclass);


--
-- Name: configuracion id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion ALTER COLUMN id SET DEFAULT nextval('public.configuracion_id_seq'::regclass);


--
-- Name: consultas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consultas ALTER COLUMN id SET DEFAULT nextval('public.consultas_id_seq'::regclass);


--
-- Name: credentials id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credentials ALTER COLUMN id SET DEFAULT nextval('public.credentials_id_seq'::regclass);


--
-- Name: database_config_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_config_logs ALTER COLUMN id SET DEFAULT nextval('public.database_config_logs_id_seq'::regclass);


--
-- Name: database_configs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_configs ALTER COLUMN id SET DEFAULT nextval('public.database_configs_id_seq'::regclass);


--
-- Name: historico_capturas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_capturas ALTER COLUMN id SET DEFAULT nextval('public.historico_capturas_id_seq'::regclass);


--
-- Name: items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items ALTER COLUMN id SET DEFAULT nextval('public.items_id_seq'::regclass);


--
-- Name: login_attempts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_attempts ALTER COLUMN id SET DEFAULT nextval('public.login_attempts_id_seq'::regclass);


--
-- Name: logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.logs ALTER COLUMN id SET DEFAULT nextval('public.logs_id_seq'::regclass);


--
-- Name: logs_aplicacion id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.logs_aplicacion ALTER COLUMN id SET DEFAULT nextval('public.logs_aplicacion_id_seq'::regclass);


--
-- Name: published_methods id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.published_methods ALTER COLUMN id SET DEFAULT nextval('public.published_methods_id_seq'::regclass);


--
-- Name: sessions id_num; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id_num SET DEFAULT nextval('public.sessions_id_num_seq'::regclass);


--
-- Name: usuarios id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id SET DEFAULT nextval('public.usuarios_id_seq'::regclass);


--
-- Name: versiones id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.versiones ALTER COLUMN id SET DEFAULT nextval('public.versiones_id_seq'::regclass);


--
-- Data for Name: app_triggers; Type: TABLE DATA; Schema: prostgles; Owner: postgres
--

COPY prostgles.app_triggers (app_id, table_name, condition, condition_hash, related_view_name, related_view_def, inserted, last_used) FROM stdin;
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	users	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:41.033688	2025-06-30 10:05:41.033688
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	global_settings	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:41.052183	2025-06-30 10:05:41.052183
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	connections	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:41.09107	2025-06-30 10:05:41.09107
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	access_control_user_types	  EXISTS ( \nSELECT 1\nFROM access_control "jd_0_access_control"\nINNER JOIN (\n SELECT *\n FROM database_configs\n) "jd_1_database_configs"\n ON "jd_0_access_control"."database_id" = "jd_1_database_configs"."id"\nWHERE (access_control_user_types."access_control_id" = "jd_0_access_control"."id") \n) 	a4a636e86496aecbd0fef60611dd68d7	\N	\N	2025-06-30 10:05:41.117907	2025-06-30 10:05:41.117907
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	connections	  EXISTS ( \nSELECT 1\nFROM (\n SELECT *\n FROM database_configs\n) "jd_0_database_configs"\nWHERE (connections."db_host" = "jd_0_database_configs"."db_host" AND connections."db_name" = "jd_0_database_configs"."db_name" AND connections."db_port" = "jd_0_database_configs"."db_port") \n) 	1d4e2baa3b25c0b582b43b43d2d3e273	\N	\N	2025-06-30 10:05:41.130738	2025-06-30 10:05:41.130738
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	database_configs	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:41.139358	2025-06-30 10:05:41.139358
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	access_control_user_types	  EXISTS ( \nSELECT 1\nFROM (\n SELECT *\n FROM access_control\n) "jd_0_access_control"\nWHERE (access_control_user_types."access_control_id" = "jd_0_access_control"."id") \n) 	ace149ed5dcd8d94b04e03cbcedcba7d	\N	\N	2025-06-30 10:05:41.645713	2025-06-30 10:05:41.645713
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	access_control_methods	  EXISTS ( \nSELECT 1\nFROM (\n SELECT *\n FROM access_control\n) "jd_0_access_control"\nWHERE (access_control_methods."access_control_id" = "jd_0_access_control"."id") \n) 	13adb92dbea3b2aae771c3f71e00d1e5	\N	\N	2025-06-30 10:05:41.686567	2025-06-30 10:05:41.686567
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	access_control	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:41.706515	2025-06-30 10:05:41.706515
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	users	"id" = '135539d6-77e8-448e-9f03-4dbaa02000f2'	ebc93ce692660804140eb017f970549a	\N	\N	2025-06-30 10:05:42.664991	2025-06-30 10:05:42.664991
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	connections	"id" IS NULL 	bd7450c8babfe7f3f79b4233852f700d	\N	\N	2025-06-30 10:05:52.96165	2025-06-30 10:05:52.96165
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	connections	"id" = '98b20426-f01b-4186-bde2-6b426b14e0c1'	496d438a6b577e3139c7c2da06cf8a07	\N	\N	2025-06-30 10:05:54.804525	2025-06-30 10:05:54.804525
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	workspaces	 (  FALSE  OR "user_id" = '135539d6-77e8-448e-9f03-4dbaa02000f2' )  AND "deleted" = false AND "id" = '45d6e9f5-b805-4151-ac68-dd5e1494a326'	ed4561a6f157482baaf5351e2fe4b9e0	\N	\N	2025-06-30 10:05:55.227031	2025-06-30 10:05:55.227031
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	links	 (  FALSE  OR "user_id" = '135539d6-77e8-448e-9f03-4dbaa02000f2' )  AND "workspace_id" = '45d6e9f5-b805-4151-ac68-dd5e1494a326'	b44a2190abdf910788f83a54ed227ae7	\N	\N	2025-06-30 10:05:55.263263	2025-06-30 10:05:55.263263
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	windows	 (  FALSE  OR "user_id" = '135539d6-77e8-448e-9f03-4dbaa02000f2' )  AND "workspace_id" = '45d6e9f5-b805-4151-ac68-dd5e1494a326'	b44a2190abdf910788f83a54ed227ae7	\N	\N	2025-06-30 10:05:55.338312	2025-06-30 10:05:55.338312
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	connections	  EXISTS ( \nSELECT 1\nFROM database_configs "jd_0_database_configs"\nINNER JOIN (\n SELECT *\n FROM alerts\n) "jd_1_alerts"\n ON "jd_0_database_configs"."id" = "jd_1_alerts"."database_config_id"\nWHERE (connections."db_host" = "jd_0_database_configs"."db_host" AND connections."db_name" = "jd_0_database_configs"."db_name" AND connections."db_port" = "jd_0_database_configs"."db_port") \n) 	ae59869c3dc2cccbe46a48c85a4e5a63	\N	\N	2025-06-30 10:05:55.948832	2025-06-30 10:05:55.948832
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	workspaces	 (  FALSE  OR "user_id" = '135539d6-77e8-448e-9f03-4dbaa02000f2' )  AND "connection_id" = '98b20426-f01b-4186-bde2-6b426b14e0c1' AND "deleted" = false	482e323b6b65fbf7a4a951563668685e	\N	\N	2025-06-30 10:05:55.972192	2025-06-30 10:05:55.972192
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	alert_viewed_by	  EXISTS ( \nSELECT 1\nFROM (\n SELECT *\n FROM alerts\n) "jd_0_alerts"\nWHERE (alert_viewed_by."alert_id" = "jd_0_alerts"."id") \n) 	b8c09369d9d127316739a385999fd6f7	\N	\N	2025-06-30 10:05:55.989565	2025-06-30 10:05:55.989565
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	alerts	  EXISTS ( \nSELECT 1\nFROM database_configs "jd_0_database_configs"\nINNER JOIN (\n SELECT *\n FROM connections\n  WHERE "id" = '98b20426-f01b-4186-bde2-6b426b14e0c1'\n) "jd_1_connections"\n ON "jd_0_database_configs"."db_host" = "jd_1_connections"."db_host" AND "jd_0_database_configs"."db_name" = "jd_1_connections"."db_name" AND "jd_0_database_configs"."db_port" = "jd_1_connections"."db_port"\nWHERE (alerts."database_config_id" = "jd_0_database_configs"."id") \n)  AND  NOT  EXISTS ( \nSELECT 1\nFROM (\n SELECT *\n FROM alert_viewed_by\n  WHERE "user_id" = '135539d6-77e8-448e-9f03-4dbaa02000f2'\n) "jd_0_alert_viewed_by"\nWHERE (alerts."id" = "jd_0_alert_viewed_by"."alert_id") \n) 	89e559653a4bd043836999c45670ed5d	\N	\N	2025-06-30 10:05:56.030798	2025-06-30 10:05:56.030798
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	llm_prompts	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:56.095234	2025-06-30 10:05:56.095234
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	codigos_items	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:56.095901	2025-06-30 10:05:56.095901
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	llm_credentials	TRUE	c0d83f0b82a6b30de8811e69e6d95c61	\N	\N	2025-06-30 10:05:56.095227	2025-06-30 10:05:56.095227
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	stats	"connection_id" = '98b20426-f01b-4186-bde2-6b426b14e0c1' AND "state" = 'active'	bdc0239948fbe9fbd9710a45cb935b90	\N	\N	2025-06-30 10:07:11.901529	2025-06-30 10:07:11.901529
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	stats	"connection_id" = '98b20426-f01b-4186-bde2-6b426b14e0c1' AND "datid" = 16387 AND "state" = 'active'	eed9dc7eb23f08ab6ab4725224be9257	\N	\N	2025-06-30 10:07:12.084712	2025-06-30 10:07:12.084712
\.


--
-- Data for Name: apps; Type: TABLE DATA; Schema: prostgles; Owner: postgres
--

COPY prostgles.apps (id, added, application_name, watching_schema_tag_names, check_frequency_ms) FROM stdin;
aa9901e0-9a3c-4f60-83fe-0d68e3dfc354	2025-06-30 10:05:40.901677	prostgles aa9901e0-9a3c-4f60-83fe-0d68e3dfc354 	\N	10000
ed942de0-1f58-492f-aa49-aefe96869a90	2025-06-30 10:05:54.748809	prostgles ed942de0-1f58-492f-aa49-aefe96869a90 	{"ALTER AGGREGATE","ALTER COLLATION","ALTER CONVERSION","ALTER DOMAIN","ALTER DEFAULT PRIVILEGES","ALTER EXTENSION","ALTER FOREIGN DATA WRAPPER","ALTER FOREIGN TABLE","ALTER FUNCTION","ALTER LANGUAGE","ALTER LARGE OBJECT","ALTER MATERIALIZED VIEW","ALTER OPERATOR","ALTER OPERATOR CLASS","ALTER OPERATOR FAMILY","ALTER POLICY","ALTER PROCEDURE","ALTER PUBLICATION","ALTER ROUTINE","ALTER SCHEMA","ALTER SEQUENCE","ALTER SERVER","ALTER STATISTICS","ALTER SUBSCRIPTION","ALTER TABLE","ALTER TEXT SEARCH CONFIGURATION","ALTER TEXT SEARCH DICTIONARY","ALTER TEXT SEARCH PARSER","ALTER TEXT SEARCH TEMPLATE","ALTER TRIGGER","ALTER TYPE","ALTER USER MAPPING","ALTER VIEW",COMMENT,"CREATE ACCESS METHOD","CREATE AGGREGATE","CREATE CAST","CREATE COLLATION","CREATE CONVERSION","CREATE DOMAIN","CREATE EXTENSION","CREATE FOREIGN DATA WRAPPER","CREATE FOREIGN TABLE","CREATE FUNCTION","CREATE INDEX","CREATE LANGUAGE","CREATE MATERIALIZED VIEW","CREATE OPERATOR","CREATE OPERATOR CLASS","CREATE OPERATOR FAMILY","CREATE POLICY","CREATE PROCEDURE","CREATE PUBLICATION","CREATE RULE","CREATE SCHEMA","CREATE SEQUENCE","CREATE SERVER","CREATE STATISTICS","CREATE SUBSCRIPTION","CREATE TABLE","CREATE TABLE AS","CREATE TEXT SEARCH CONFIGURATION","CREATE TEXT SEARCH DICTIONARY","CREATE TEXT SEARCH PARSER","CREATE TEXT SEARCH TEMPLATE","CREATE TRIGGER","CREATE TYPE","CREATE USER MAPPING","CREATE VIEW","DROP ACCESS METHOD","DROP AGGREGATE","DROP CAST","DROP COLLATION","DROP CONVERSION","DROP DOMAIN","DROP EXTENSION","DROP FOREIGN DATA WRAPPER","DROP FOREIGN TABLE","DROP FUNCTION","DROP INDEX","DROP LANGUAGE","DROP MATERIALIZED VIEW","DROP OPERATOR","DROP OPERATOR CLASS","DROP OPERATOR FAMILY","DROP OWNED","DROP POLICY","DROP PROCEDURE","DROP PUBLICATION","DROP ROUTINE","DROP RULE","DROP SCHEMA","DROP SEQUENCE","DROP SERVER","DROP STATISTICS","DROP SUBSCRIPTION","DROP TABLE","DROP TEXT SEARCH CONFIGURATION","DROP TEXT SEARCH DICTIONARY","DROP TEXT SEARCH PARSER","DROP TEXT SEARCH TEMPLATE","DROP TRIGGER","DROP TYPE","DROP USER MAPPING","DROP VIEW",GRANT,"IMPORT FOREIGN SCHEMA","REFRESH MATERIALIZED VIEW",REVOKE,"SECURITY LABEL","SELECT INTO"}	10000
\.


--
-- Data for Name: versions; Type: TABLE DATA; Schema: prostgles; Owner: postgres
--

COPY prostgles.versions (version, schema_md5, added_at) FROM stdin;
4.2.239	2c08daca07ce8b44ddcb6d84590ef4cf	2025-06-30 10:04:03.470547
\.


--
-- Data for Name: access_control; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.access_control (id, name, database_id, llm_daily_limit, "dbsPermissions", "dbPermissions", created) FROM stdin;
\.


--
-- Data for Name: access_control_allowed_llm; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.access_control_allowed_llm (access_control_id, llm_credential_id, llm_prompt_id) FROM stdin;
\.


--
-- Data for Name: access_control_connections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.access_control_connections (connection_id, access_control_id) FROM stdin;
\.


--
-- Data for Name: access_control_methods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.access_control_methods (published_method_id, access_control_id) FROM stdin;
\.


--
-- Data for Name: access_control_user_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.access_control_user_types (access_control_id, user_type) FROM stdin;
\.


--
-- Data for Name: alert_viewed_by; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alert_viewed_by (id, alert_id, user_id, viewed) FROM stdin;
\.


--
-- Data for Name: alerts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alerts (id, title, message, severity, database_config_id, connection_id, section, data, created) FROM stdin;
\.


--
-- Data for Name: backups; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.backups (id, connection_id, connection_details, credential_id, destination, dump_command, restore_command, local_filepath, content_type, initiator, details, status, uploaded, restore_status, restore_start, restore_end, restore_logs, dump_logs, "dbSizeInBytes", "sizeInBytes", created, last_updated, options, restore_options) FROM stdin;
\.


--
-- Data for Name: capturas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.capturas (id, codigo, item, motivo, cumple, usuario, fecha) FROM stdin;
19	010101010101010101010	444444	Instrucciones de cuidado	NO CUMPLE	admin	2025-07-07 16:07:01.177058
\.


--
-- Data for Name: clp_carga_detalle; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clp_carga_detalle (id, clp_carga_id, codigo_barras, item_id) FROM stdin;
1	7	29860000298099001010	3817
2	7	29860000298099101017	3817
3	7	29860000298099201014	3817
4	7	29860000298100801015	3818
5	7	29860000298101001010	3819
6	7	29860000298101101017	3819
7	7	29860000298102301012	744
8	7	29860000298103201016	3820
9	7	29860000298103301013	3820
10	7	29860000298103401010	3820
11	7	29860000298103501017	3820
12	7	29860000298103601014	3820
13	7	29860000298104301014	959
14	7	29860000298104401011	959
15	7	29860000298104501018	959
16	7	29860000298106701014	1272
17	7	29860000298106801011	3821
18	7	29860000298106901018	3821
19	7	29860000298107001016	3822
20	7	29860000298107101013	3822
21	7	29860000298107401014	1242
22	7	29860000298107601018	961
23	7	29860000298107801012	456
24	7	29860000298111201011	486
25	7	29860000298113501014	3823
26	7	29860000298113701018	3824
27	7	29860000298113901012	3825
28	7	29860000298114001010	3826
29	7	29860000298114101017	3826
30	7	29860000298114201014	3826
31	7	29860000298114501015	3827
32	7	29860000298099501015	3828
33	7	29860000298099601012	3829
34	7	29860000298100901012	3830
35	7	29860000298101701019	3831
36	7	29860000298101801016	3831
37	7	29860000298101901013	3831
38	7	29860000298102001011	3831
39	7	29860000298102101018	3831
40	7	29860000298102201015	3831
41	7	29860000298112001018	3832
42	7	29860000298112101015	3832
43	7	29860000298112201012	3832
44	7	29860000298112301019	3832
45	7	29860000298112401016	3833
46	7	29860000298112501013	3833
47	7	29860000298112601010	3833
48	7	29860000298112701017	3833
49	7	29860000298112801014	3833
50	7	29860000298112901011	3833
51	7	29860000298113001019	3833
52	7	29860000298113101016	3833
53	7	29860000298113201013	3833
54	7	29860000298114301011	3834
55	7	29860000298114401018	3834
56	7	29900000169205101010	3835
57	7	29900000169205201017	3835
58	7	29900000169205301014	3835
59	7	29900000169205401011	3835
60	7	29900000169205501018	3835
61	7	29900000169205601015	3835
62	7	29900000169205701012	3835
63	7	29900000169205801019	3835
64	7	29900000169205901016	3835
65	7	29900000169206001014	3835
66	7	29900000169208101013	3835
67	7	29900000169211901019	3836
68	7	29900000169212001017	3836
69	7	29900000169212101014	3836
70	7	29860000298115401019	3837
71	7	29860000298115501016	3837
72	7	29860000298171701018	215
73	7	29860000298171801015	215
74	7	29860000298171901012	215
75	7	29860000298172001010	215
76	7	29860000298173301012	3838
77	7	29860000298173401019	3838
78	7	29860000298173501016	3838
79	7	29860000298173601013	3838
80	7	29860000298173701010	3838
81	7	29860000298173801017	3838
82	7	29860000298173901014	3838
83	7	29860000298174001012	3838
84	7	29860000298174101019	3838
85	7	29860000298174201016	3838
86	7	29860000298174301013	3838
87	7	29860000298118901017	3839
88	7	29860000298123701015	3840
89	7	29860000298123801012	3840
90	7	29860000298123901019	3840
91	7	29860000298124001017	3840
92	7	29860000298124101014	220
93	7	29860000298124201011	220
94	7	29860000298124301018	220
95	7	29860000298124401015	220
96	7	29860000298124501012	220
97	7	29860000298124601019	220
98	7	29860000298125301019	3841
99	7	29860000298125401016	3841
100	7	29860000298125501013	3841
101	7	29860000298126301010	3842
102	7	29860000298130401018	3843
103	7	29860000298130501015	3843
104	7	29860000298130601012	3843
105	7	29860000298130701019	3843
106	7	29860000298130801016	3843
107	7	29860000298130901013	3843
108	7	29860000298131001011	3843
109	7	29860000298131101018	3843
110	7	29860000298134901017	227
111	7	29860000298116501017	811
112	7	29860000298116601014	811
113	7	29860000298116701011	811
114	7	29860000298116801018	811
115	7	29860000298117401011	811
116	7	29860000298117501018	3844
117	7	29860000298117601015	3844
118	7	29860000298118101011	1447
119	7	29860000298118201018	1447
120	7	29860000298118301015	1447
121	7	29860000298118401012	1447
122	7	29860000298121401012	3845
123	7	29860000298121501019	3845
124	7	29860000298121601016	3845
125	7	29860000298121701013	3845
126	7	29860000298121801010	3845
127	7	29860000298121901017	3845
128	7	29860000298122001015	3845
129	7	29860000298122101012	3845
130	7	29860000298122201019	3845
131	7	29860000298122301016	3845
132	7	29860000298125601010	3846
133	7	29860000298128301012	1176
134	7	29860000298128401019	3847
135	7	29860000298129001012	3848
136	7	29860000298129101019	3848
137	7	29860000298129401010	666
138	7	29860000298129501017	666
139	7	29860000298129601014	666
140	7	29860000298129701011	25
141	7	29860000298133601015	3849
142	7	29860000298135701014	2317
143	7	29860000298116901015	811
144	7	29860000298117001013	811
145	7	29860000298117101010	811
146	7	29860000298117201017	811
147	7	29860000298117301014	811
148	7	29860000298117701012	3850
149	7	29860000298117801019	3850
150	7	29860000298117901016	3851
151	7	29860000298118601016	3852
152	7	29860000298118701013	3852
153	7	29860000298126201013	3853
154	7	29860000298126401017	496
155	7	29860000298126501014	498
156	7	29860000298126601011	499
157	7	29860000298126701018	499
158	7	29860000298127001010	3854
159	7	29860000298129801018	3843
160	7	29860000298129901015	3843
161	7	29860000298130001010	3843
162	7	29860000298130101017	3843
163	7	29860000298130201014	3843
164	7	29860000298130301011	3843
165	7	29860000298132501017	3855
166	7	29860000298133401011	3112
167	7	29860000298136301017	3856
168	7	29860000298170701017	3857
169	7	29860000298171101016	3858
170	7	29860000298172201014	3859
171	7	29860000298172301011	3859
172	7	29860000298172401018	2237
173	7	29860000298172901013	1777
174	7	29860000298173001011	3860
175	7	29860000298173101018	3860
176	7	29860000298173201015	3861
177	7	29860000298175101010	3832
178	7	29860000298175201017	3832
179	7	29860000298175301014	3832
180	7	29860000298175401011	3832
181	7	29860000298175501018	3832
182	7	29860000298175601015	3832
183	7	29860000298175701012	3832
184	7	29860000298116401010	1504
185	7	29860000298118001014	1200
186	7	29860000298119801011	3862
187	7	29860000298119901018	3862
188	7	29860000298121001014	3863
189	7	29860000298121101011	3863
190	7	29860000298121201018	3864
191	7	29860000298121301015	3864
192	7	29860000298122401013	3845
193	7	29860000298122501010	3845
194	7	29860000298122601017	3845
195	7	29860000298122701014	3845
196	7	29860000298122801011	3845
197	7	29860000298122901018	3845
198	7	29860000298123001016	3845
199	7	29860000298123101013	3845
200	7	29860000298123201010	3845
201	7	29860000298123301017	3845
202	7	29860000298124701016	3865
203	7	29860000298132901015	3866
204	7	29860000298133301014	2338
205	7	29860000298134301015	484
206	7	29860000298134401012	484
207	7	29860000298135601017	3867
208	7	29860000298136001016	401
209	7	29860000298136101013	2821
210	7	29860000297710601017	3868
211	7	29860000297723001015	3869
212	7	29860000297760101017	3870
213	7	29860000297927501016	3871
214	7	29860000297928801018	3872
215	7	29860000297929301014	3873
216	7	29860000297929401011	3873
217	7	29860000297936901010	271
218	7	29860000297991701013	3874
219	7	29860000297992101012	3875
220	7	29860000297992301016	3872
221	7	29860000297992501010	3873
222	7	29860000297999701011	3876
223	7	29860000297999801018	3876
224	7	29860000297999901015	3877
225	7	29860000298000001018	3877
226	7	29860000298000101015	3878
227	7	29860000298000201012	3878
228	7	29860000298000301019	3879
229	7	29860000298000401016	3879
230	7	29860000298000501013	3880
231	7	29860000298000601010	3880
232	7	29860000298000701017	3881
233	7	29860000298000801014	3882
234	7	29860000298192701013	558
235	7	29862500654160201010	3883
236	7	29862500654160201010	3883
237	7	29862500654162201012	3884
238	7	29862500654162201012	3885
239	7	29862500654162201012	3886
240	7	29862500654162801014	3887
241	7	29862500654177801016	2626
242	7	29862500654177801016	3104
243	7	29862500654177801016	1501
244	7	29862500654177801016	3888
245	7	29862500654177801016	3889
246	7	29862500654177801016	3890
247	7	29862500654177801016	3891
248	7	29862500654178401019	3892
249	7	29862500654178401019	3893
250	7	29862500654178401019	3894
251	7	29862500654178401019	3895
252	7	29862500654178701010	3896
253	7	29862500654178701010	3892
254	7	29862500654178701010	3893
255	7	29862500654178701010	3897
256	7	29862500654178701010	3894
257	7	29862500654183001013	3898
258	7	29862500654183101010	3899
259	7	29862500654183101010	3900
260	7	29862500654299201011	3901
261	7	29862500654299201011	3901
262	7	29862500654299201011	3902
263	7	29862500654299201011	3903
264	7	29862500654299201011	3904
265	7	29862500654299201011	3905
266	7	29862500654299201011	3906
267	7	29862500654299201011	3907
268	7	29862500654299201011	3908
269	7	29862500654301401015	3909
270	7	29862500654301401015	3910
271	7	29862500654301401015	3910
272	7	29862500654301401015	3911
273	7	29862500654301401015	3912
274	7	29862500654301401015	3913
275	7	29862500654301401015	3914
276	7	29862500654301401015	3914
277	7	29862500654301401015	319
278	7	29862500654301401015	3915
279	7	29862500654301401015	3916
280	7	29862500654301401015	3917
281	7	29862500654301401015	3918
282	7	29862500654301401015	3919
283	7	29862500654301401015	3920
284	7	29862500654301401015	3920
285	7	29862500654301401015	3921
286	7	29862500654301401015	3922
287	7	29862500654301401015	3923
288	7	29862500654301401015	3924
289	7	29862500654301401015	3925
290	7	29862500654301401015	3926
291	7	29862500654301401015	3927
292	7	29862500654301401015	3928
293	7	29862500654301501012	3929
294	7	29862500654301501012	3909
295	7	29862500654301501012	3930
296	7	29862500654301501012	3931
297	7	29862500654301501012	3912
298	7	29862500654301501012	3932
299	7	29862500654301501012	3933
300	7	29862500654301501012	319
301	7	29862500654301501012	3915
302	7	29862500654301501012	3934
303	7	29862500654301501012	3916
304	7	29862500654301501012	3935
305	7	29862500654301501012	3918
306	7	29862500654301501012	3919
307	7	29862500654301501012	3920
308	7	29862500654301501012	3921
309	7	29862500654301501012	3922
310	7	29862500654301501012	3936
311	7	29862500654301501012	3937
312	7	29862500654301501012	3938
313	7	29862500654301501012	3938
314	7	29862500654301501012	3939
315	7	29862500654301501012	3924
316	7	29862500654301501012	3925
317	7	29862500654301501012	3926
318	7	29862500654301501012	3927
319	7	29862500654301501012	3928
320	7	29862500654301501012	3940
321	7	29862500654302101015	3941
322	7	29862500654302101015	3942
323	7	29862500654302101015	3939
324	7	29862500654302201012	3943
325	7	29862500654302201012	3909
326	7	29862500654302201012	3909
327	7	29862500654302201012	3944
328	7	29862500654302201012	3945
329	7	29862500654302201012	3914
330	7	29862500654302201012	319
331	7	29862500654302201012	3917
332	7	29862500654302201012	3946
333	7	29862500654302201012	3947
334	7	29862500654302201012	3935
335	7	29862500654302201012	3918
336	7	29862500654302201012	3919
337	7	29862500654302201012	3920
338	7	29862500654302201012	3921
339	7	29862500654302201012	3948
340	7	29862500654302201012	3922
341	7	29862500654302201012	3938
342	7	29862500654302201012	3949
343	7	29862500654302201012	3950
344	7	29862500654302201012	3924
345	7	29862500654302201012	3925
346	7	29862500654302201012	3926
347	7	29862500654302201012	3927
348	7	29862500654302201012	3928
349	7	29862500654302201012	3951
350	7	29870000012133601012	910
351	7	29870000012136001013	3952
352	7	29870000012136101010	3952
353	7	29872500654344301010	3953
354	7	29860000297941701018	1283
355	7	29860000297991801010	3874
356	7	29860000297991901017	3954
357	7	29860000297992601017	3873
358	7	29860000297995301019	3955
359	7	29860000297995401016	3955
360	7	29860000297995501013	3955
361	7	29860000297995601010	3955
362	7	29860000297995801014	2318
363	7	29860000297995901011	2318
364	7	29862500654144601018	3956
365	7	29862500654144601018	3957
366	7	29862500654144601018	3958
367	7	29862500654144601018	3959
368	7	29862500654144601018	2697
369	7	29862500654144601018	2698
370	7	29862500654144601018	2699
371	7	29862500654144601018	3960
372	7	29862500654144601018	3961
373	7	29862500654144601018	3962
374	7	29862500654185101012	3963
375	7	29862500654185101012	3963
376	7	29862500654185101012	3964
377	7	29862500654185101012	3965
378	7	29862500654185101012	3965
379	7	29862500654185201019	3964
380	7	29862500654185201019	3964
381	7	29862500654185201019	3965
382	7	29862500654185201019	3965
383	7	29862500654185301016	3964
384	7	29862500654185301016	3964
385	7	29862500654185301016	3964
386	7	29862500654185301016	3965
387	7	29862500654185301016	3965
388	7	29862500654185401013	3964
389	7	29862500654185401013	3965
390	7	29862500654185401013	3965
391	7	29862500654225701013	2266
392	7	29862500654225701013	3011
393	7	29862500654225701013	2267
394	7	29862500654225701013	3012
395	7	29862500654225701013	3013
396	7	29862500654226401013	2435
397	7	29862500654227001016	3966
398	7	29862500654227101013	2436
399	7	29862500654296901017	3901
400	7	29862500654296901017	3901
401	7	29862500654296901017	3967
402	7	29862500654296901017	3968
403	7	29862500654296901017	3969
404	7	29862500654296901017	3970
405	7	29862500654296901017	3903
406	7	29862500654296901017	3904
407	7	29862500654296901017	3906
408	7	29862500654296901017	3971
409	7	29862500654296901017	3907
410	7	29862500654296901017	3908
411	7	29862500654296901017	3972
412	7	29862500654296901017	3973
413	7	29862500654296901017	3974
414	7	29862500654297001015	3901
415	7	29862500654297001015	258
416	7	29862500654297001015	258
417	7	29862500654297001015	3903
418	7	29862500654297001015	3904
419	7	29862500654297001015	3971
420	7	29862500654297001015	3908
421	7	29862500654297201019	3901
422	7	29862500654297201019	3901
423	7	29862500654297201019	3968
424	7	29862500654297201019	3975
425	7	29862500654297201019	3976
426	7	29862500654297201019	3977
427	7	29862500654297201019	3978
428	7	29862500654297201019	3979
429	7	29862500654297201019	3903
430	7	29862500654297201019	3904
431	7	29862500654297201019	3980
432	7	29862500654297201019	3906
433	7	29862500654297201019	3906
434	7	29862500654297201019	3908
435	7	29862500654297201019	3981
436	7	29862500654297201019	3982
437	7	29862500654297201019	3982
438	7	29862500654297501010	3901
439	7	29862500654297501010	3901
440	7	29862500654297501010	3967
441	7	29862500654297501010	3967
442	7	29862500654297501010	3967
443	7	29862500654297501010	3968
444	7	29862500654297501010	3968
445	7	29862500654297501010	3968
446	7	29862500654297501010	3968
447	7	29862500654297501010	3968
448	7	29862500654297501010	3902
449	7	29862500654297501010	3977
450	7	29862500654297501010	2688
451	7	29862500654297501010	3176
452	7	29862500654297501010	3983
453	7	29862500654297501010	3903
454	7	29862500654297501010	3904
455	7	29862500654297501010	3906
456	7	29862500654297501010	3971
457	7	29862500654297501010	3971
458	7	29862500654297501010	3907
459	7	29862500654297501010	3907
460	7	29862500654297501010	3984
461	7	29862500654297501010	3908
462	7	29862500654297501010	3985
463	7	29862500654298601018	3901
464	7	29862500654298601018	3901
465	7	29862500654298601018	3903
466	7	29862500654298601018	3904
467	7	29862500654298601018	3980
468	7	29862500654298601018	3906
469	7	29862500654298601018	3971
470	7	29862500654298601018	3986
471	7	29862500654298701015	3968
472	7	29862500654298701015	3968
473	7	29862500654298701015	3987
474	7	29862500654298701015	3903
475	7	29862500654298701015	3904
476	7	29862500654298701015	3906
477	7	29862500654298701015	3971
478	7	29862500654298701015	3907
479	7	29862500654298701015	3908
480	7	29862500654298701015	1712
481	7	29862500654298701015	1712
482	7	29862500654298801012	3901
483	7	29862500654298801012	3968
484	7	29862500654298801012	3968
485	7	29862500654298801012	2969
486	7	29862500654298801012	3976
487	7	29862500654298801012	3977
488	7	29862500654298801012	3903
489	7	29862500654298801012	3904
490	7	29862500654298801012	3906
491	7	29862500654298801012	3971
492	7	29862500654298801012	3907
493	7	29862500654328701017	3349
494	7	29862500654328701017	3988
495	7	29862500654328701017	3989
496	7	29862500654393401010	2416
497	7	29862500654440101012	2767
498	7	29862500654458201014	3990
499	7	29862500654458201014	3991
500	7	29862500654458401018	3990
501	7	29862500654458401018	3991
502	7	29862500654458501015	3990
503	7	29862500654458501015	3991
504	7	29862500654465001014	3992
505	7	29862500654465001014	3990
506	7	29862500654465001014	3991
507	7	29862500654465101011	3990
508	7	29862500654465101011	3991
509	7	29862500654465201018	3990
510	7	29862500654465201018	3991
511	7	29862500654465601016	3990
512	7	29862500654465601016	3991
513	7	29862500654469501013	3993
514	7	29862500654469601010	3993
515	7	29862500654469801014	3993
516	7	29862500654469901011	3993
517	7	29862500654470001016	3993
518	7	29862500654470101013	3993
519	7	29862500654470201010	3993
520	7	29862500654470301017	3993
521	7	29862500654470401014	3993
522	7	29862500654480401011	3910
523	7	29862500654480401011	3930
524	7	29862500654480401011	3994
525	7	29862500654480401011	3995
526	7	29862500654480401011	3992
527	7	29862500654480401011	3996
528	7	29862500654480401011	3997
529	7	29862500654480401011	3998
530	7	29862500654480401011	3999
531	7	29862500654480401011	4000
532	7	29862500654480401011	4001
533	7	29862500654480401011	4002
534	7	29862500654480401011	4003
535	7	29862500654480401011	4004
536	7	29862500654480401011	4005
537	7	29862500654480401011	4006
538	7	29862500654480401011	4007
539	7	29862500654480401011	4008
540	7	29862500654480401011	4009
541	7	29862500654480401011	4010
542	7	29862500654480401011	4011
543	7	29862500654480401011	4012
544	7	29862500654480401011	4013
545	7	29862500654480401011	4014
546	7	29862500654480401011	4015
547	7	29862500654480401011	312
548	7	29862500654480401011	141
549	7	29862500654480401011	4016
550	7	29862500654480401011	4017
551	7	29862500654480401011	4018
552	7	29862500654480401011	4019
553	7	29862500654480401011	4020
554	7	29862500654480401011	4021
555	7	29862500654480401011	4022
556	7	29862500654480401011	4023
557	7	29862500654480401011	4024
558	7	29862500654480401011	4025
559	7	29862500654480401011	4026
560	7	29862500654480401011	3204
561	7	29862500654480401011	2204
562	7	29862500654480401011	2536
563	7	29862500654480401011	4027
564	7	29862500654483101013	4028
565	7	29862500654483201010	4028
566	7	29862500654483301017	4028
567	7	29862500654483901019	4029
568	7	29862500654484101014	4028
569	7	29862500654484101014	4030
570	7	29862500654484301018	4031
571	7	29862500654484301018	4032
572	7	29862500654484301018	4033
573	7	29862500654484301018	4034
574	7	29860000297992201019	3875
575	7	29860000298002301011	4035
576	7	29860000298177301016	4036
577	7	29860000298178201010	4037
578	7	29860000298178501011	2773
579	7	29860000298180301016	116
580	7	29860000298180401013	4038
581	7	29860000298180501010	4039
582	7	29860000298180701014	4040
583	7	29860000298181001016	1979
584	7	29860000298181701015	792
585	7	29860000298181801012	792
586	7	29860000298181901019	1326
587	7	29860000298182001017	1326
588	7	29860000298182701016	764
589	7	29860000298182901010	1889
590	7	29860000298183001018	2556
591	7	29860000298184101016	2036
592	7	29860000298184301010	1547
593	7	29860000298184601011	1664
594	7	29860000298185901013	4041
595	7	29860000298188501018	4042
596	7	29860000298188801019	4043
597	7	29860000298189101011	4044
598	7	29860000298189501019	4045
599	7	29860000298189701013	4046
600	7	29860000298190401010	4047
601	7	29860000298190501017	4048
602	7	29860000298191301014	925
603	7	29860000298191401011	4049
604	7	29860000298191501018	828
605	7	29860000298191601015	4050
606	7	29862500654368901019	2251
607	7	29862500654369301018	1580
608	7	29862500654369301018	4051
609	7	29862500654369301018	2766
610	7	29862500654369301018	2767
611	7	29862500654369301018	2768
612	7	29862500654369401015	4052
613	7	29862500654369401015	4051
614	7	29862500654369401015	4053
615	7	29862500654369401015	3898
616	7	29862500654369401015	4054
617	7	29862500654369401015	4055
618	7	29862500654369401015	4056
619	7	29862500654369401015	4057
620	7	29862500654369401015	4058
621	7	29862500654369401015	4058
622	7	29862500654369401015	2768
623	7	29862500654369501012	4059
624	7	29862500654369501012	4059
625	7	29862500654369501012	3001
626	7	29862500654369501012	3898
627	7	29862500654369501012	2768
628	7	29862500654474901013	4060
629	7	29862500654475101018	4060
630	7	29862500654475101018	4060
631	7	29862500654476201016	4061
632	7	29862500654476401010	4062
633	7	29862500654476401010	4063
634	7	29862500654481301015	4064
635	7	29862500654481301015	4065
636	7	29862500654481301015	4066
637	7	29862500654481301015	4067
638	7	29862500654481301015	4068
639	7	29862500654481401012	4069
640	7	29862500654481401012	4067
641	7	29862500654481501019	4067
642	7	29862500654482701014	4070
643	7	29862500654482701014	4071
644	7	29862500654482701014	4072
645	7	29862500654482701014	4067
646	7	29862500654482701014	4073
647	7	29862500654482801011	4070
648	7	29862500654482801011	4067
649	7	29862500654483401014	4074
650	7	29862500654483401014	4064
651	7	29862500654483401014	4067
652	7	29862500654483401014	4075
653	7	29862500654483401014	4076
654	7	29862500654484201011	3913
655	7	29862500654484501012	3017
656	7	29862500654484601019	3017
657	7	29860000297996101016	4077
658	7	29860000297996201013	4077
659	7	29860000297996301010	4077
660	7	29860000297996401017	4077
661	7	29860000297996501014	1386
662	7	29860000297996601011	438
663	7	29860000297996701018	438
664	7	29860000297998501016	11
665	7	29860000297998601013	4078
666	7	29860000297998901014	4079
667	7	29860000297999001012	4079
668	7	29860000297999101019	4079
669	7	29860000297999401010	4080
670	7	29860000297999501017	4080
671	7	29860000297999601014	4080
672	7	29860000298001001019	4081
673	7	29860000298001101016	4081
674	7	29860000298001201013	4081
675	7	29860000298001301010	4081
676	7	29860000298001401017	4082
677	7	29860000298001501014	4082
678	7	29860000298001601011	4082
679	7	29860000298001701018	4082
680	7	29860000298001801015	4082
681	7	29860000298001901012	4083
682	7	29860000298002001010	4083
683	7	29860000298002101017	4083
684	7	29860000298002401018	1534
685	7	29860000298181201010	2582
686	7	29860000298183101015	2423
687	7	29860000298183601010	2584
688	7	29860000298184901012	3252
689	7	29862500654237101010	4084
690	7	29862500654237201017	4084
691	7	29862500654237301014	4084
692	7	29862500654237401011	4084
693	7	29862500654237501018	4084
694	7	29862500654237601015	4084
695	7	29862500654237701012	4084
696	7	29900000169148401011	4085
697	7	29870000012133501015	4086
698	7	29872500654206701011	4087
699	7	29872500654206801018	4088
700	7	29872500654206901015	4087
701	7	29872500654335101010	4089
702	7	29872500654335601015	4089
703	7	29872500654335801019	4088
704	7	29872500654336001014	4087
705	7	29872500654336201018	4088
706	7	29872500654336501019	4087
707	7	29872500654344901012	4090
708	7	29872500654442101015	4091
709	7	29872500654442301019	4092
710	7	29872500654442401016	4090
711	7	29890000018229401012	4093
712	7	29890000018229501019	4093
713	7	29890000018229601016	4093
714	7	29890000018229701013	4093
715	7	29890000018229801010	4093
716	7	29890000018229901017	4093
717	7	29890000018228801019	4093
718	7	29890000018228901016	4093
719	7	29890000018229001014	4093
720	7	29890000018229101011	4093
721	7	29890000018229201018	4093
722	7	29890000018229301015	4093
723	7	29890000018230601014	4094
724	7	29890000018230701011	4094
725	7	29890000018230801018	4094
726	7	29890000018230901015	4094
727	7	29890000018231001013	4094
728	7	29890000018231101010	4094
729	7	29890000018231201017	4094
730	7	29890000018231301014	4094
731	7	29890000018231401011	4094
732	7	29890000018231501018	4094
733	7	29890000018231601015	4094
734	7	29890000018231701012	4094
735	7	29890000018233201019	4095
736	7	29890000018233301016	4095
737	7	29890000018233701014	4096
738	7	29890000018233801011	4096
739	7	29890000018233901018	4096
740	7	29890000018234001016	4096
741	7	29890000018234101013	4096
742	7	29890000018234201010	4096
743	7	29890000018234301017	4096
744	7	29890000018234401014	4096
745	7	29890000018234501011	4096
746	7	29890000018234601018	4096
747	7	29890000018230001012	4093
748	7	29890000018230101019	4093
749	7	29890000018230201016	4093
750	7	29890000018230301013	4093
751	7	29890000018230401010	4093
752	7	29890000018230501017	4093
753	7	29890000018232801010	4097
754	7	29890000018232901017	4097
755	7	29890000018233001015	4098
756	7	29890000018233101012	4098
757	7	29890000018233401013	4099
758	7	29890000018233501010	4099
759	7	29890000018233601017	4099
760	7	29890000018231801019	4094
761	7	29890000018231901016	4094
762	7	29890000018232001014	4094
763	7	29890000018232101011	4094
764	7	29890000018232201018	4094
765	7	29890000018232301015	4094
766	7	29890000018232401012	4094
767	7	29890000018232501019	4100
768	7	29890000018232601016	4100
769	7	29890000018232701013	4101
770	7	29860000297921901018	4102
771	7	29860000297922001016	27
772	7	29860000297922101013	27
773	7	29860000297922401014	2619
774	7	29860000297931001012	4103
775	7	29860000297932501018	4104
776	7	29860000297933801010	2901
777	7	29860000297933901017	2253
778	7	29860000297936701016	271
779	7	29860000297940201012	4105
780	7	29860000297940501013	1220
781	7	29860000297990201017	4106
782	7	29860000297990301014	1603
783	7	29860000297990401011	2138
784	7	29860000297990501018	4107
785	7	29860000297990701012	779
786	7	29860000297990801019	779
787	7	29860000297991601016	2262
788	7	29860000297996001019	438
789	7	29860000297998301012	2262
790	7	29860000298177501010	1312
791	7	29860000298177701014	4108
792	7	29860000298177801011	4109
793	7	29860000298177901018	1293
794	7	29860000298178001016	2222
795	7	29860000298178101013	4110
796	7	29860000298180601017	2665
797	7	29860000298192901017	4111
798	7	29860000298193101012	4112
799	7	29860000298193201019	4113
800	7	29860000298193501010	4114
801	7	29860000298193601017	4114
802	7	29860000298193701014	4114
803	7	29860000298193801011	4115
804	7	29860000298193901018	4116
805	7	29860000298194001016	2952
806	7	29860000298194101013	1886
807	7	29860000298194301017	4117
808	7	29860000298194901019	4118
809	7	29860000298195001017	4118
810	7	29860000298195101014	4118
811	7	29860000298195201011	4119
812	7	29860000298195301018	4120
813	7	29860000298195401015	2151
814	7	29860000298195501012	4121
815	7	29860000298195601019	4122
816	7	29860000298195701016	4123
817	7	29860000298196001018	4124
818	7	29860000298196101015	125
819	7	29862500654145001017	4125
820	7	29862500654145001017	4126
821	7	29862500654145001017	4127
822	7	29862500654145001017	4128
823	7	29860000298153701016	2842
824	7	29860000298154001018	4129
825	7	29860000298154101015	4130
826	7	29860000298154201012	4131
827	7	29860000298154901011	4132
828	7	29860000298155001019	4132
829	7	29860000298155101016	4133
830	7	29860000298155201013	4133
831	7	29860000298155401017	1674
832	7	29860000298155501014	1674
833	7	29860000298155601011	1674
834	7	29860000298157801017	4134
835	7	29860000298160101018	373
836	7	29860000298161101019	4135
837	7	29860000298161301013	4136
838	7	29860000298161401010	4137
839	7	29860000298161701011	4138
840	7	29860000298161801018	4139
841	7	29860000298162201017	1926
842	7	29860000298163901017	87
843	7	29860000298164001015	87
844	7	29860000298164101012	87
845	7	29860000298164201019	87
846	7	29860000298164901018	525
847	7	29860000298165001016	525
848	7	29860000298165701015	4140
849	7	29860000298165801012	4140
850	7	29860000298166101014	4141
851	7	29860000298166201011	840
852	7	29860000298167501013	1185
853	7	29860000298168901012	234
854	7	29860000298169001010	234
855	7	29860000298169401018	441
856	7	29860000298169501015	441
857	7	29860000298169601012	441
858	7	29860000298169701019	441
859	7	29860000298169801016	441
860	7	29860000298170301019	4142
861	7	29860000298170401016	4142
862	7	29860000298153501012	4143
863	7	29860000298153601019	2841
864	7	29860000298153801013	1210
865	7	29860000298154301019	4144
866	7	29860000298154401016	4145
867	7	29860000298156301011	4146
868	7	29860000298156701019	635
869	7	29860000298156801016	635
870	7	29860000298156901013	701
871	7	29860000298157301012	1665
872	7	29860000298157401019	1665
873	7	29860000298157501016	1665
874	7	29860000298157701010	4134
875	7	29860000298157901014	4147
876	7	29860000298158001012	4147
877	7	29860000298158101019	4147
878	7	29860000298158201016	4147
879	7	29860000298158301013	4147
880	7	29860000298158401010	4148
881	7	29860000298158501017	4148
882	7	29860000298158601014	4148
883	7	29860000298158701011	4148
884	7	29860000298158801018	4148
885	7	29860000298158901015	4148
886	7	29860000298160401019	76
887	7	29860000298160501016	76
888	7	29860000298161001012	4149
889	7	29860000298161501017	4138
890	7	29860000298161601014	4138
891	7	29860000298162001013	423
892	7	29860000298162101010	4150
893	7	29860000298162501018	4151
894	7	29860000298163101011	217
895	7	29860000298163201018	217
896	7	29860000298163401012	4152
897	7	29860000298163501019	4152
898	7	29860000298165201010	451
899	7	29860000298166001017	4153
900	7	29860000298166301018	3268
901	7	29860000298167601010	4154
902	7	29860000298167701017	4154
903	7	29860000298169101017	4155
904	7	29860000298169201014	4155
905	7	29860000298169301011	4155
906	7	29860000298169901013	4156
907	7	29860000298170001018	1626
908	7	29860000298170101015	1626
909	7	29860000298170201012	560
910	7	29860000297922201010	4157
911	7	29860000297922301017	4158
912	7	29860000297922501011	4159
913	7	29860000297943901014	3389
914	7	29860000297989201019	4160
915	7	29860000297995701017	2704
916	7	29860000297998701010	4078
917	7	29860000297998801017	1534
918	7	29860000297999201016	4079
919	7	29860000298198501015	3954
920	7	29862500654275501014	3896
921	7	29862500654275501014	3893
922	7	29862500654287701017	1713
923	7	29862500654301901010	4161
924	7	29862500654301901010	4162
925	7	29862500654301901010	4163
926	7	29862500654301901010	4164
927	7	29862500654365301014	3903
928	7	29862500654365301014	3904
929	7	29862500654365301014	3971
930	7	29862500654365301014	3907
931	7	29862500654365401011	3968
932	7	29862500654365401011	4165
933	7	29862500654365401011	3903
934	7	29862500654365401011	3904
935	7	29862500654365401011	3971
936	7	29862500654365401011	3907
937	7	29862500654365601015	3901
938	7	29862500654365601015	3903
939	7	29862500654365601015	3904
940	7	29862500654365601015	3971
941	7	29862500654365601015	3971
942	7	29862500654365601015	3907
943	7	29862500654365601015	3908
944	7	29862500654365801019	3901
945	7	29862500654365801019	3969
946	7	29862500654365801019	4166
947	7	29862500654365801019	2969
948	7	29862500654365801019	3903
949	7	29862500654365801019	3904
950	7	29862500654365801019	3908
951	7	29862500654387801015	4167
952	7	29862500654402101016	4168
953	7	29862500654402401017	4168
954	7	29862500654402501014	4168
955	7	29862500654402601011	4168
956	7	29862500654402601011	4168
957	7	29862500654402701018	4168
958	7	29862500654402701018	4168
959	7	29862500654402801015	4168
960	7	29862500654403001010	4168
961	7	29862500654403201014	4168
962	7	29862500654403501015	4168
963	7	29862500654403701019	4168
964	7	29862500654403701019	4168
965	7	29862500654404701010	3962
966	7	29862500654404801017	3962
967	7	29862500654404901014	3962
968	7	29862500654476501017	4060
969	7	29862500654476501017	4063
970	7	29862500654476501017	4169
971	7	29862500654477201017	4170
972	7	29862500654477301014	4170
973	7	29862500654480501018	4069
974	7	29862500654480501018	4171
975	7	29862500654480501018	4172
976	7	29862500654480501018	4173
977	7	29862500654480501018	3935
978	7	29862500654480501018	4174
979	7	29862500654480901016	4175
980	7	29862500654481001014	4000
981	7	29862500654481001014	4018
982	7	29862500654481001014	4067
983	7	29862500654481001014	4176
984	7	29862500654481101011	4177
985	7	29862500654481101011	4067
986	7	29862500654481201018	4178
987	7	29862500654481201018	3990
988	7	29862500654481201018	4067
989	7	29862500654481701013	4179
990	7	29862500654481701013	4180
991	7	29862500654481701013	4181
992	7	29862500654481701013	3946
993	7	29862500654481701013	4182
994	7	29862500654481701013	4067
995	7	29862500654481701013	3045
996	7	29862500654481701013	4183
997	7	29862500654481701013	3923
998	7	29862500654481701013	4184
999	7	29862500654484701016	4185
1000	7	29862500654484701016	4072
1001	7	29862500654484801013	4068
1002	7	29862500654485101015	4074
1003	7	29862500654485101015	4186
1004	7	29862500654485101015	4187
1005	7	29862500654485101015	4188
1006	7	29862500654500601010	3970
1007	7	29862500654500701017	3970
1008	7	29862500654500901011	3890
1009	7	29862500654501001019	4189
1010	7	29862500654501001019	3913
1011	7	29862500654501001019	4190
1012	7	29862500654501201013	4190
1013	7	29862500654501201013	4067
1014	7	29862500654501301010	4191
1015	7	29870000012131101015	4192
1016	7	29900000169182401013	4193
1017	7	29900000169182501010	4193
1018	7	29900000169182601017	4193
1019	7	29900000169182701014	4193
1020	7	29900000169182801011	4193
1021	7	29900000169182901018	4193
1022	7	29900000169183001016	4193
1023	7	29900000169183101013	4193
1024	7	29900000169183201010	4193
1025	7	29900000169183301017	4193
1026	7	29900000169183401014	4193
1027	7	29900000169183501011	4193
1028	7	29900000169183601018	4193
1029	7	29900000169183701015	4193
1030	7	29900000169183801012	4193
1031	7	29900000169183901019	4193
1032	7	29900000169184001017	4193
1033	7	29900000169184101014	4193
1034	7	29900000169184201011	4193
1035	7	29900000169184301018	4193
1036	7	29900000169184401015	4193
1037	7	29900000169184501012	4193
1038	7	29900000169184601019	4193
1039	7	29900000169184701016	4193
1040	7	29900000169184801013	4193
1041	7	29900000169184901010	4193
1042	7	29900000169185001018	4193
1043	7	29900000169185101015	4194
1044	7	29900000169185201012	4194
1045	7	29900000169185301019	4194
1046	7	29900000169185401016	4194
1047	7	29900000169185501013	4194
1048	7	29900000169185601010	4194
1049	7	29900000169185701017	4194
1050	7	29900000169185801014	4194
1051	7	29900000169185901011	4194
1052	7	29900000169186001019	4194
1053	7	29900000169186101016	4194
1054	7	29900000169186201013	4194
1055	7	29900000169186301010	4194
1056	7	29900000169221801019	4195
1057	7	29900000169221901016	4195
1058	7	29900000169222001014	4195
1059	7	29900000169222101011	4195
1060	7	29900000169222201018	4195
1061	7	29900000169222301015	4195
1062	7	29900000169222401012	4195
1063	7	29900000169222501019	4195
1064	7	29900000169222601016	4196
1065	7	29900000169222701013	4196
1066	7	29900000169222801010	4196
1067	7	29900000169222901017	4196
1068	7	29900000169223001015	4196
1069	7	29900000169223101012	4196
1070	7	29900000169223201019	4196
1071	7	29900000169223301016	4196
1072	7	29900000169223401013	4196
1073	7	29900000169223501010	4196
1074	7	29900000169223601017	4196
1075	7	29900000169223701014	4196
1076	7	29900000169223801011	4196
1077	7	29900000169223901018	4196
1078	7	29900000169224001016	4196
1079	7	29900000169224101013	4196
1080	7	29900000169224201010	4196
1081	7	29900000169224301017	4196
1082	7	29900000169227501014	4197
1083	7	29900000169227601011	4197
1084	7	29900000169227701018	4197
1085	7	29900000169227801015	4197
1086	7	29900000169227901012	4197
1087	7	29900000169228001010	4197
1088	7	29900000169224401014	4198
1089	7	29900000169224501011	4198
1090	7	29900000169224601018	4198
1091	7	29900000169225501012	4199
1092	7	29900000169225601019	4199
1093	7	29900000169225701016	4199
1094	7	29900000169225801013	4199
1095	7	29900000169225901010	4199
1096	7	29900000169226001018	4199
1097	7	29900000169226101015	4199
1098	7	29900000169226201012	4199
1099	7	29900000169226301019	4199
1100	7	29900000169226401016	4199
1101	7	29900000169226501013	4199
1102	7	29900000169226701017	4200
1103	7	29900000169226801014	4200
1104	7	29900000169226901011	4200
1105	7	29900000169227001019	4200
1106	7	29900000169227101016	4200
1107	7	29900000169227201013	4200
1108	7	29900000169283401015	4201
1109	7	29900000169283501012	4201
1110	7	29900000169283601019	4201
1111	7	29900000169283701016	4201
1112	7	29900000169283801013	4201
1113	7	29900000169283901010	4201
1114	7	29900000169284001018	4201
1115	7	29900000169284101015	4201
1116	7	29900000169284201012	4201
1117	7	29900000169284301019	4201
1118	7	29900000169284401016	4201
1119	7	29900000169284501013	4201
1120	7	29900000169284601010	4201
1121	7	29900000169284701017	4201
1122	7	29900000169284801014	4201
1123	7	29900000169284901011	4201
1124	7	29900000169285001019	4201
1125	7	29900000169285101016	4201
1126	7	29900000169285201013	4201
1127	7	29900000169285301010	4201
1128	7	29900000169285401017	4201
1129	7	29900000169285501014	4201
1130	7	29900000169285601011	4201
1131	7	29900000169285701018	4201
1132	7	29900000169285801015	4201
1133	7	29900000169285901012	4201
1134	7	29900000169286001010	4201
1135	7	29900000169286101017	4201
1136	7	29900000169286201014	4201
1137	7	29900000169286301011	4201
1138	7	29900000169224701015	4202
1139	7	29900000169224801012	4202
1140	7	29900000169224901019	4202
1141	7	29900000169225001017	4202
1142	7	29900000169225101014	4202
1143	7	29900000169225201011	4202
1144	7	29900000169225301018	4202
1145	7	29900000169226601010	2832
1146	7	29900000169227301010	829
1147	7	29900000169227401017	829
1148	7	29870000012143601019	4203
1149	7	29870000012143701016	4203
1150	7	29870000012143801013	4203
1151	7	29870000012143901010	4203
1152	7	29870000012144001018	4203
1153	7	29870000012144201012	4203
1154	7	29870000012144301019	4203
1155	7	29870000012144401016	4203
1156	7	29870000012144501013	4203
1157	7	29870000012144601010	4203
1158	7	29870000012144701017	4203
1159	7	29870000012144801014	4203
1160	7	29870000012144901011	4203
1161	7	29870000012145001019	4203
1162	7	29870000012145101016	4203
1163	7	29870000012147701010	4204
1164	7	29870000012148001012	4205
1165	7	29870000012148101019	4205
1166	7	29870000012148201016	4205
1167	7	29900000169180101010	4206
1168	7	29900000169180201017	4206
1169	7	29900000169180301014	4206
1170	7	29900000169180401011	4206
1171	7	29900000169180501018	4206
1172	7	29900000169180601015	4206
1173	7	29900000169180701012	4206
1174	7	29900000169180801019	4206
1175	7	29900000169180901016	4206
1176	7	29900000169181001014	4206
1177	7	29900000169181101011	4206
1178	7	29900000169181201018	4206
1179	7	29900000169181301015	4206
1180	7	29900000169181401012	4206
1181	7	29900000169181501019	4206
1182	7	29900000169181601016	4206
1183	7	29900000169181701013	4206
1184	7	29900000169194601016	4207
1185	7	29900000169194701013	4207
1186	7	29900000169194801010	4207
1187	7	29900000169194901017	4207
1188	7	29900000169195001015	4207
1189	7	29900000169195101012	4207
1190	7	29900000169195201019	4207
1191	7	29900000169195301016	4207
1192	7	29900000169195401013	4207
1193	7	29900000169195501010	4207
1194	7	29900000169195601017	4207
1195	7	29900000169195701014	4207
1196	7	29900000169195801011	4207
1197	7	29900000169195901018	4207
1198	7	29900000169196001016	4207
1199	7	29900000169196101013	4207
1200	7	29900000169196201010	4207
1201	7	29900000169196301017	4207
1202	7	29900000169196401014	4207
1203	7	29900000169196501011	4207
1204	7	29900000169196601018	4207
1205	7	29900000169196701015	4207
1206	7	29900000169177401011	4208
1207	7	29900000169177501018	4208
1208	7	29900000169177601015	4208
1209	7	29900000169177701012	4208
1210	7	29900000169177801019	4208
1211	7	29900000169177901016	4208
1212	7	29900000169178001014	4208
1213	7	29870000012144101015	4203
1214	7	29870000012145201013	4209
1215	7	29870000012145301010	4209
1216	7	29870000012145401017	4209
1217	7	29870000012145501014	4209
1218	7	29870000012147801017	4210
1219	7	29870000012147901014	4211
1220	7	29870000012148301013	4212
1221	7	29870000012148401010	4212
1222	7	29870000012148501017	4213
1223	7	29870000012148601014	4213
1224	7	29870000012148701011	4214
1225	7	29870000012148901015	4215
1226	7	29870000012149001013	4215
1227	7	29870000012149101010	4215
1228	7	29870000012149201017	4215
1229	7	29870000012149301014	4215
1230	7	29870000012149401011	4216
1231	7	29870000012149501018	4216
\.


--
-- Data for Name: clp_cargas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clp_cargas (id, archivo, usuario, fecha_carga, codigos_agregados) FROM stdin;
1	CLP_2900220358 - MX.xls	admin	\N	1107
2	CLP_2900220358 - MX.xls	admin	\N	835
3	CLP_2900220358 - MX.xls	admin	\N	0
4	CLP_2900220358 - MX.xls	admin	\N	495
5	CLP_2900220358 - MX.xls	admin	\N	197
6	CLP_2900220358 - MX.xls	admin	\N	868
7	CLP_2900220358 - MX.xls	admin	\N	0
\.


--
-- Data for Name: codigos_barras; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.codigos_barras (id, codigo_barras, item_id) FROM stdin;
2636	29860000298099001010	3817
2637	29860000298099101017	3817
2638	29860000298099201014	3817
2639	29860000298100801015	3818
2640	29860000298101001010	3819
2641	29860000298101101017	3819
2642	29860000298102301012	744
2643	29860000298103201016	3820
2644	29860000298103301013	3820
2645	29860000298103401010	3820
2646	29860000298103501017	3820
2647	29860000298103601014	3820
2648	29860000298104301014	959
2649	29860000298104401011	959
2650	29860000298104501018	959
2651	29860000298106701014	1272
2652	29860000298106801011	3821
2653	29860000298106901018	3821
2654	29860000298107001016	3822
2655	29860000298107101013	3822
2656	29860000298107401014	1242
2657	29860000298107601018	961
2658	29860000298107801012	456
2659	29860000298111201011	486
2660	29860000298113501014	3823
2661	29860000298113701018	3824
2662	29860000298113901012	3825
2663	29860000298114001010	3826
2664	29860000298114101017	3826
2665	29860000298114201014	3826
2666	29860000298114501015	3827
2667	29860000298099501015	3828
2668	29860000298099601012	3829
2669	29860000298100901012	3830
2670	29860000298101701019	3831
2671	29860000298101801016	3831
2672	29860000298101901013	3831
2673	29860000298102001011	3831
2674	29860000298102101018	3831
2675	29860000298102201015	3831
2676	29860000298112001018	3832
2677	29860000298112101015	3832
2678	29860000298112201012	3832
2679	29860000298112301019	3832
2680	29860000298112401016	3833
2681	29860000298112501013	3833
2682	29860000298112601010	3833
2683	29860000298112701017	3833
2684	29860000298112801014	3833
2685	29860000298112901011	3833
2686	29860000298113001019	3833
2687	29860000298113101016	3833
2688	29860000298113201013	3833
2689	29860000298114301011	3834
2690	29860000298114401018	3834
2691	29900000169205101010	3835
2692	29900000169205201017	3835
2693	29900000169205301014	3835
2694	29900000169205401011	3835
2695	29900000169205501018	3835
2696	29900000169205601015	3835
2697	29900000169205701012	3835
2698	29900000169205801019	3835
2699	29900000169205901016	3835
2700	29900000169206001014	3835
2701	29900000169208101013	3835
2702	29900000169211901019	3836
2703	29900000169212001017	3836
2704	29900000169212101014	3836
2705	29860000298115401019	3837
2706	29860000298115501016	3837
2707	29860000298171701018	215
2708	29860000298171801015	215
2709	29860000298171901012	215
2710	29860000298172001010	215
2711	29860000298173301012	3838
2712	29860000298173401019	3838
2713	29860000298173501016	3838
2714	29860000298173601013	3838
2715	29860000298173701010	3838
2716	29860000298173801017	3838
2717	29860000298173901014	3838
2718	29860000298174001012	3838
2719	29860000298174101019	3838
2720	29860000298174201016	3838
2721	29860000298174301013	3838
2722	29860000298118901017	3839
2723	29860000298123701015	3840
2724	29860000298123801012	3840
2725	29860000298123901019	3840
2726	29860000298124001017	3840
2727	29860000298124101014	220
2728	29860000298124201011	220
2729	29860000298124301018	220
2730	29860000298124401015	220
2731	29860000298124501012	220
2732	29860000298124601019	220
2733	29860000298125301019	3841
2734	29860000298125401016	3841
2735	29860000298125501013	3841
2736	29860000298126301010	3842
2737	29860000298130401018	3843
2738	29860000298130501015	3843
2739	29860000298130601012	3843
2740	29860000298130701019	3843
2741	29860000298130801016	3843
2742	29860000298130901013	3843
2743	29860000298131001011	3843
2744	29860000298131101018	3843
2745	29860000298134901017	227
2746	29860000298116501017	811
2747	29860000298116601014	811
2748	29860000298116701011	811
2749	29860000298116801018	811
2750	29860000298117401011	811
2751	29860000298117501018	3844
2752	29860000298117601015	3844
2753	29860000298118101011	1447
2754	29860000298118201018	1447
2755	29860000298118301015	1447
2756	29860000298118401012	1447
2757	29860000298121401012	3845
2758	29860000298121501019	3845
2759	29860000298121601016	3845
2760	29860000298121701013	3845
2761	29860000298121801010	3845
2762	29860000298121901017	3845
2763	29860000298122001015	3845
2764	29860000298122101012	3845
2765	29860000298122201019	3845
2766	29860000298122301016	3845
2767	29860000298125601010	3846
2768	29860000298128301012	1176
2769	29860000298128401019	3847
2770	29860000298129001012	3848
2771	29860000298129101019	3848
2772	29860000298129401010	666
2773	29860000298129501017	666
2774	29860000298129601014	666
2775	29860000298129701011	25
2776	29860000298133601015	3849
2777	29860000298135701014	2317
2778	29860000298116901015	811
2779	29860000298117001013	811
2780	29860000298117101010	811
2781	29860000298117201017	811
2782	29860000298117301014	811
2783	29860000298117701012	3850
2784	29860000298117801019	3850
2785	29860000298117901016	3851
2786	29860000298118601016	3852
2787	29860000298118701013	3852
2788	29860000298126201013	3853
2789	29860000298126401017	496
2790	29860000298126501014	498
2791	29860000298126601011	499
2792	29860000298126701018	499
2793	29860000298127001010	3854
2794	29860000298129801018	3843
2795	29860000298129901015	3843
2796	29860000298130001010	3843
2797	29860000298130101017	3843
2798	29860000298130201014	3843
2799	29860000298130301011	3843
2800	29860000298132501017	3855
2801	29860000298133401011	3112
2802	29860000298136301017	3856
2803	29860000298170701017	3857
2804	29860000298171101016	3858
2805	29860000298172201014	3859
2806	29860000298172301011	3859
2807	29860000298172401018	2237
2808	29860000298172901013	1777
2809	29860000298173001011	3860
2810	29860000298173101018	3860
2811	29860000298173201015	3861
2812	29860000298175101010	3832
2813	29860000298175201017	3832
2814	29860000298175301014	3832
2815	29860000298175401011	3832
2816	29860000298175501018	3832
2817	29860000298175601015	3832
2818	29860000298175701012	3832
2819	29860000298116401010	1504
2820	29860000298118001014	1200
2821	29860000298119801011	3862
2822	29860000298119901018	3862
2823	29860000298121001014	3863
2824	29860000298121101011	3863
2825	29860000298121201018	3864
2826	29860000298121301015	3864
2827	29860000298122401013	3845
2828	29860000298122501010	3845
2829	29860000298122601017	3845
2830	29860000298122701014	3845
2831	29860000298122801011	3845
2832	29860000298122901018	3845
2833	29860000298123001016	3845
2834	29860000298123101013	3845
2835	29860000298123201010	3845
2836	29860000298123301017	3845
2837	29860000298124701016	3865
2838	29860000298132901015	3866
2839	29860000298133301014	2338
2840	29860000298134301015	484
2841	29860000298134401012	484
2842	29860000298135601017	3867
2843	29860000298136001016	401
2844	29860000298136101013	2821
2845	29860000297710601017	3868
2846	29860000297723001015	3869
2847	29860000297760101017	3870
2848	29860000297927501016	3871
2849	29860000297928801018	3872
2850	29860000297929301014	3873
2851	29860000297929401011	3873
2852	29860000297936901010	271
2853	29860000297991701013	3874
2854	29860000297992101012	3875
2855	29860000297992301016	3872
2856	29860000297992501010	3873
2857	29860000297999701011	3876
2858	29860000297999801018	3876
2859	29860000297999901015	3877
2860	29860000298000001018	3877
2861	29860000298000101015	3878
2862	29860000298000201012	3878
2863	29860000298000301019	3879
2864	29860000298000401016	3879
2865	29860000298000501013	3880
2866	29860000298000601010	3880
2867	29860000298000701017	3881
2868	29860000298000801014	3882
2869	29860000298192701013	558
2870	29862500654160201010	3883
2871	29862500654162201012	3884
2872	29862500654162801014	3887
2873	29862500654177801016	2626
2874	29862500654178401019	3892
2875	29862500654178701010	3896
2876	29862500654183001013	3898
2877	29862500654183101010	3899
2878	29862500654299201011	3901
2879	29862500654301401015	3909
2880	29862500654301501012	3929
2881	29862500654302101015	3941
2882	29862500654302201012	3943
2883	29870000012133601012	910
2884	29870000012136001013	3952
2885	29870000012136101010	3952
2886	29872500654344301010	3953
2887	29860000297941701018	1283
2888	29860000297991801010	3874
2889	29860000297991901017	3954
2890	29860000297992601017	3873
2891	29860000297995301019	3955
2892	29860000297995401016	3955
2893	29860000297995501013	3955
2894	29860000297995601010	3955
2895	29860000297995801014	2318
2896	29860000297995901011	2318
2897	29862500654144601018	3956
2898	29862500654185101012	3963
2899	29862500654185201019	3964
2900	29862500654185301016	3964
2901	29862500654185401013	3964
2902	29862500654225701013	2266
2903	29862500654226401013	2435
2904	29862500654227001016	3966
2905	29862500654227101013	2436
2906	29862500654296901017	3901
2907	29862500654297001015	3901
2908	29862500654297201019	3901
2909	29862500654297501010	3901
2910	29862500654298601018	3901
2911	29862500654298701015	3968
2912	29862500654298801012	3901
2913	29862500654328701017	3349
2914	29862500654393401010	2416
2915	29862500654440101012	2767
2916	29862500654458201014	3990
2917	29862500654458401018	3990
2918	29862500654458501015	3990
2919	29862500654465001014	3992
2920	29862500654465101011	3990
2921	29862500654465201018	3990
2922	29862500654465601016	3990
2923	29862500654469501013	3993
2924	29862500654469601010	3993
2925	29862500654469801014	3993
2926	29862500654469901011	3993
2927	29862500654470001016	3993
2928	29862500654470101013	3993
2929	29862500654470201010	3993
2930	29862500654470301017	3993
2931	29862500654470401014	3993
2932	29862500654480401011	3910
2933	29862500654483101013	4028
2934	29862500654483201010	4028
2935	29862500654483301017	4028
2936	29862500654483901019	4029
2937	29862500654484101014	4028
2938	29862500654484301018	4031
2939	29860000297992201019	3875
2940	29860000298002301011	4035
2941	29860000298177301016	4036
2942	29860000298178201010	4037
2943	29860000298178501011	2773
2944	29860000298180301016	116
2945	29860000298180401013	4038
2946	29860000298180501010	4039
2947	29860000298180701014	4040
2948	29860000298181001016	1979
2949	29860000298181701015	792
2950	29860000298181801012	792
2951	29860000298181901019	1326
2952	29860000298182001017	1326
2953	29860000298182701016	764
2954	29860000298182901010	1889
2955	29860000298183001018	2556
2956	29860000298184101016	2036
2957	29860000298184301010	1547
2958	29860000298184601011	1664
2959	29860000298185901013	4041
2960	29860000298188501018	4042
2961	29860000298188801019	4043
2962	29860000298189101011	4044
2963	29860000298189501019	4045
2964	29860000298189701013	4046
2965	29860000298190401010	4047
2966	29860000298190501017	4048
2967	29860000298191301014	925
2968	29860000298191401011	4049
2969	29860000298191501018	828
2970	29860000298191601015	4050
2971	29862500654368901019	2251
2972	29862500654369301018	1580
2973	29862500654369401015	4052
2974	29862500654369501012	4059
2975	29862500654474901013	4060
2976	29862500654475101018	4060
2977	29862500654476201016	4061
2978	29862500654476401010	4062
2979	29862500654481301015	4064
2980	29862500654481401012	4069
2981	29862500654481501019	4067
2982	29862500654482701014	4070
2983	29862500654482801011	4070
2984	29862500654483401014	4074
2985	29862500654484201011	3913
2986	29862500654484501012	3017
2987	29862500654484601019	3017
2988	29860000297996101016	4077
2989	29860000297996201013	4077
2990	29860000297996301010	4077
2991	29860000297996401017	4077
2992	29860000297996501014	1386
2993	29860000297996601011	438
2994	29860000297996701018	438
2995	29860000297998501016	11
2996	29860000297998601013	4078
2997	29860000297998901014	4079
2998	29860000297999001012	4079
2999	29860000297999101019	4079
3000	29860000297999401010	4080
3001	29860000297999501017	4080
3002	29860000297999601014	4080
3003	29860000298001001019	4081
3004	29860000298001101016	4081
3005	29860000298001201013	4081
3006	29860000298001301010	4081
3007	29860000298001401017	4082
3008	29860000298001501014	4082
3009	29860000298001601011	4082
3010	29860000298001701018	4082
3011	29860000298001801015	4082
3012	29860000298001901012	4083
3013	29860000298002001010	4083
3014	29860000298002101017	4083
3015	29860000298002401018	1534
3016	29860000298181201010	2582
3017	29860000298183101015	2423
3018	29860000298183601010	2584
3019	29860000298184901012	3252
3020	29862500654237101010	4084
3021	29862500654237201017	4084
3022	29862500654237301014	4084
3023	29862500654237401011	4084
3024	29862500654237501018	4084
3025	29862500654237601015	4084
3026	29862500654237701012	4084
3027	29900000169148401011	4085
3028	29870000012133501015	4086
3029	29872500654206701011	4087
3030	29872500654206801018	4088
3031	29872500654206901015	4087
3032	29872500654335101010	4089
3033	29872500654335601015	4089
3034	29872500654335801019	4088
3035	29872500654336001014	4087
3036	29872500654336201018	4088
3037	29872500654336501019	4087
3038	29872500654344901012	4090
3039	29872500654442101015	4091
3040	29872500654442301019	4092
3041	29872500654442401016	4090
3042	29890000018229401012	4093
3043	29890000018229501019	4093
3044	29890000018229601016	4093
3045	29890000018229701013	4093
3046	29890000018229801010	4093
3047	29890000018229901017	4093
3048	29890000018228801019	4093
3049	29890000018228901016	4093
3050	29890000018229001014	4093
3051	29890000018229101011	4093
3052	29890000018229201018	4093
3053	29890000018229301015	4093
3054	29890000018230601014	4094
3055	29890000018230701011	4094
3056	29890000018230801018	4094
3057	29890000018230901015	4094
3058	29890000018231001013	4094
3059	29890000018231101010	4094
3060	29890000018231201017	4094
3061	29890000018231301014	4094
3062	29890000018231401011	4094
3063	29890000018231501018	4094
3064	29890000018231601015	4094
3065	29890000018231701012	4094
3066	29890000018233201019	4095
3067	29890000018233301016	4095
3068	29890000018233701014	4096
3069	29890000018233801011	4096
3070	29890000018233901018	4096
3071	29890000018234001016	4096
3072	29890000018234101013	4096
3073	29890000018234201010	4096
3074	29890000018234301017	4096
3075	29890000018234401014	4096
3076	29890000018234501011	4096
3077	29890000018234601018	4096
3078	29890000018230001012	4093
3079	29890000018230101019	4093
3080	29890000018230201016	4093
3081	29890000018230301013	4093
3082	29890000018230401010	4093
3083	29890000018230501017	4093
3084	29890000018232801010	4097
3085	29890000018232901017	4097
3086	29890000018233001015	4098
3087	29890000018233101012	4098
3088	29890000018233401013	4099
3089	29890000018233501010	4099
3090	29890000018233601017	4099
3091	29890000018231801019	4094
3092	29890000018231901016	4094
3093	29890000018232001014	4094
3094	29890000018232101011	4094
3095	29890000018232201018	4094
3096	29890000018232301015	4094
3097	29890000018232401012	4094
3098	29890000018232501019	4100
3099	29890000018232601016	4100
3100	29890000018232701013	4101
3101	29860000297921901018	4102
3102	29860000297922001016	27
3103	29860000297922101013	27
3104	29860000297922401014	2619
3105	29860000297931001012	4103
3106	29860000297932501018	4104
3107	29860000297933801010	2901
3108	29860000297933901017	2253
3109	29860000297936701016	271
3110	29860000297940201012	4105
3111	29860000297940501013	1220
3112	29860000297990201017	4106
3113	29860000297990301014	1603
3114	29860000297990401011	2138
3115	29860000297990501018	4107
3116	29860000297990701012	779
3117	29860000297990801019	779
3118	29860000297991601016	2262
3119	29860000297996001019	438
3120	29860000297998301012	2262
3121	29860000298177501010	1312
3122	29860000298177701014	4108
3123	29860000298177801011	4109
3124	29860000298177901018	1293
3125	29860000298178001016	2222
3126	29860000298178101013	4110
3127	29860000298180601017	2665
3128	29860000298192901017	4111
3129	29860000298193101012	4112
3130	29860000298193201019	4113
3131	29860000298193501010	4114
3132	29860000298193601017	4114
3133	29860000298193701014	4114
3134	29860000298193801011	4115
3135	29860000298193901018	4116
3136	29860000298194001016	2952
3137	29860000298194101013	1886
3138	29860000298194301017	4117
3139	29860000298194901019	4118
3140	29860000298195001017	4118
3141	29860000298195101014	4118
3142	29860000298195201011	4119
3143	29860000298195301018	4120
3144	29860000298195401015	2151
3145	29860000298195501012	4121
3146	29860000298195601019	4122
3147	29860000298195701016	4123
3148	29860000298196001018	4124
3149	29860000298196101015	125
3150	29862500654145001017	4125
3151	29860000298153701016	2842
3152	29860000298154001018	4129
3153	29860000298154101015	4130
3154	29860000298154201012	4131
3155	29860000298154901011	4132
3156	29860000298155001019	4132
3157	29860000298155101016	4133
3158	29860000298155201013	4133
3159	29860000298155401017	1674
3160	29860000298155501014	1674
3161	29860000298155601011	1674
3162	29860000298157801017	4134
3163	29860000298160101018	373
3164	29860000298161101019	4135
3165	29860000298161301013	4136
3166	29860000298161401010	4137
3167	29860000298161701011	4138
3168	29860000298161801018	4139
3169	29860000298162201017	1926
3170	29860000298163901017	87
3171	29860000298164001015	87
3172	29860000298164101012	87
3173	29860000298164201019	87
3174	29860000298164901018	525
3175	29860000298165001016	525
3176	29860000298165701015	4140
3177	29860000298165801012	4140
3178	29860000298166101014	4141
3179	29860000298166201011	840
3180	29860000298167501013	1185
3181	29860000298168901012	234
3182	29860000298169001010	234
3183	29860000298169401018	441
3184	29860000298169501015	441
3185	29860000298169601012	441
3186	29860000298169701019	441
3187	29860000298169801016	441
3188	29860000298170301019	4142
3189	29860000298170401016	4142
3190	29860000298153501012	4143
3191	29860000298153601019	2841
3192	29860000298153801013	1210
3193	29860000298154301019	4144
3194	29860000298154401016	4145
3195	29860000298156301011	4146
3196	29860000298156701019	635
3197	29860000298156801016	635
3198	29860000298156901013	701
3199	29860000298157301012	1665
3200	29860000298157401019	1665
3201	29860000298157501016	1665
3202	29860000298157701010	4134
3203	29860000298157901014	4147
3204	29860000298158001012	4147
3205	29860000298158101019	4147
3206	29860000298158201016	4147
3207	29860000298158301013	4147
3208	29860000298158401010	4148
3209	29860000298158501017	4148
3210	29860000298158601014	4148
3211	29860000298158701011	4148
3212	29860000298158801018	4148
3213	29860000298158901015	4148
3214	29860000298160401019	76
3215	29860000298160501016	76
3216	29860000298161001012	4149
3217	29860000298161501017	4138
3218	29860000298161601014	4138
3219	29860000298162001013	423
3220	29860000298162101010	4150
3221	29860000298162501018	4151
3222	29860000298163101011	217
3223	29860000298163201018	217
3224	29860000298163401012	4152
3225	29860000298163501019	4152
3226	29860000298165201010	451
3227	29860000298166001017	4153
3228	29860000298166301018	3268
3229	29860000298167601010	4154
3230	29860000298167701017	4154
3231	29860000298169101017	4155
3232	29860000298169201014	4155
3233	29860000298169301011	4155
3234	29860000298169901013	4156
3235	29860000298170001018	1626
3236	29860000298170101015	1626
3237	29860000298170201012	560
3238	29860000297922201010	4157
3239	29860000297922301017	4158
3240	29860000297922501011	4159
3241	29860000297943901014	3389
3242	29860000297989201019	4160
3243	29860000297995701017	2704
3244	29860000297998701010	4078
3245	29860000297998801017	1534
3246	29860000297999201016	4079
3247	29860000298198501015	3954
3248	29862500654275501014	3896
3249	29862500654287701017	1713
3250	29862500654301901010	4161
3251	29862500654365301014	3903
3252	29862500654365401011	3968
3253	29862500654365601015	3901
3254	29862500654365801019	3901
3255	29862500654387801015	4167
3256	29862500654402101016	4168
3257	29862500654402401017	4168
3258	29862500654402501014	4168
3259	29862500654402601011	4168
3260	29862500654402701018	4168
3261	29862500654402801015	4168
3262	29862500654403001010	4168
3263	29862500654403201014	4168
3264	29862500654403501015	4168
3265	29862500654403701019	4168
3266	29862500654404701010	3962
3267	29862500654404801017	3962
3268	29862500654404901014	3962
3269	29862500654476501017	4060
3270	29862500654477201017	4170
3271	29862500654477301014	4170
3272	29862500654480501018	4069
3273	29862500654480901016	4175
3274	29862500654481001014	4000
3275	29862500654481101011	4177
3276	29862500654481201018	4178
3277	29862500654481701013	4179
3278	29862500654484701016	4185
3279	29862500654484801013	4068
3280	29862500654485101015	4074
3281	29862500654500601010	3970
3282	29862500654500701017	3970
3283	29862500654500901011	3890
3284	29862500654501001019	4189
3285	29862500654501201013	4190
3286	29862500654501301010	4191
3287	29870000012131101015	4192
3288	29900000169182401013	4193
3289	29900000169182501010	4193
3290	29900000169182601017	4193
3291	29900000169182701014	4193
3292	29900000169182801011	4193
3293	29900000169182901018	4193
3294	29900000169183001016	4193
3295	29900000169183101013	4193
3296	29900000169183201010	4193
3297	29900000169183301017	4193
3298	29900000169183401014	4193
3299	29900000169183501011	4193
3300	29900000169183601018	4193
3301	29900000169183701015	4193
3302	29900000169183801012	4193
3303	29900000169183901019	4193
3304	29900000169184001017	4193
3305	29900000169184101014	4193
3306	29900000169184201011	4193
3307	29900000169184301018	4193
3308	29900000169184401015	4193
3309	29900000169184501012	4193
3310	29900000169184601019	4193
3311	29900000169184701016	4193
3312	29900000169184801013	4193
3313	29900000169184901010	4193
3314	29900000169185001018	4193
3315	29900000169185101015	4194
3316	29900000169185201012	4194
3317	29900000169185301019	4194
3318	29900000169185401016	4194
3319	29900000169185501013	4194
3320	29900000169185601010	4194
3321	29900000169185701017	4194
3322	29900000169185801014	4194
3323	29900000169185901011	4194
3324	29900000169186001019	4194
3325	29900000169186101016	4194
3326	29900000169186201013	4194
3327	29900000169186301010	4194
3328	29900000169221801019	4195
3329	29900000169221901016	4195
3330	29900000169222001014	4195
3331	29900000169222101011	4195
3332	29900000169222201018	4195
3333	29900000169222301015	4195
3334	29900000169222401012	4195
3335	29900000169222501019	4195
3336	29900000169222601016	4196
3337	29900000169222701013	4196
3338	29900000169222801010	4196
3339	29900000169222901017	4196
3340	29900000169223001015	4196
3341	29900000169223101012	4196
3342	29900000169223201019	4196
3343	29900000169223301016	4196
3344	29900000169223401013	4196
3345	29900000169223501010	4196
3346	29900000169223601017	4196
3347	29900000169223701014	4196
3348	29900000169223801011	4196
3349	29900000169223901018	4196
3350	29900000169224001016	4196
3351	29900000169224101013	4196
3352	29900000169224201010	4196
3353	29900000169224301017	4196
3354	29900000169227501014	4197
3355	29900000169227601011	4197
3356	29900000169227701018	4197
3357	29900000169227801015	4197
3358	29900000169227901012	4197
3359	29900000169228001010	4197
3360	29900000169224401014	4198
3361	29900000169224501011	4198
3362	29900000169224601018	4198
3363	29900000169225501012	4199
3364	29900000169225601019	4199
3365	29900000169225701016	4199
3366	29900000169225801013	4199
3367	29900000169225901010	4199
3368	29900000169226001018	4199
3369	29900000169226101015	4199
3370	29900000169226201012	4199
3371	29900000169226301019	4199
3372	29900000169226401016	4199
3373	29900000169226501013	4199
3374	29900000169226701017	4200
3375	29900000169226801014	4200
3376	29900000169226901011	4200
3377	29900000169227001019	4200
3378	29900000169227101016	4200
3379	29900000169227201013	4200
3380	29900000169283401015	4201
3381	29900000169283501012	4201
3382	29900000169283601019	4201
3383	29900000169283701016	4201
3384	29900000169283801013	4201
3385	29900000169283901010	4201
3386	29900000169284001018	4201
3387	29900000169284101015	4201
3388	29900000169284201012	4201
3389	29900000169284301019	4201
3390	29900000169284401016	4201
3391	29900000169284501013	4201
3392	29900000169284601010	4201
3393	29900000169284701017	4201
3394	29900000169284801014	4201
3395	29900000169284901011	4201
3396	29900000169285001019	4201
3397	29900000169285101016	4201
3398	29900000169285201013	4201
3399	29900000169285301010	4201
3400	29900000169285401017	4201
3401	29900000169285501014	4201
3402	29900000169285601011	4201
3403	29900000169285701018	4201
3404	29900000169285801015	4201
3405	29900000169285901012	4201
3406	29900000169286001010	4201
3407	29900000169286101017	4201
3408	29900000169286201014	4201
3409	29900000169286301011	4201
3410	29900000169224701015	4202
3411	29900000169224801012	4202
3412	29900000169224901019	4202
3413	29900000169225001017	4202
3414	29900000169225101014	4202
3415	29900000169225201011	4202
3416	29900000169225301018	4202
3417	29900000169226601010	2832
3418	29900000169227301010	829
3419	29900000169227401017	829
3420	29870000012143601019	4203
3421	29870000012143701016	4203
3422	29870000012143801013	4203
3423	29870000012143901010	4203
3424	29870000012144001018	4203
3425	29870000012144201012	4203
3426	29870000012144301019	4203
3427	29870000012144401016	4203
3428	29870000012144501013	4203
3429	29870000012144601010	4203
3430	29870000012144701017	4203
3431	29870000012144801014	4203
3432	29870000012144901011	4203
3433	29870000012145001019	4203
3434	29870000012145101016	4203
3435	29870000012147701010	4204
3436	29870000012148001012	4205
3437	29870000012148101019	4205
3438	29870000012148201016	4205
3439	29900000169180101010	4206
3440	29900000169180201017	4206
3441	29900000169180301014	4206
3442	29900000169180401011	4206
3443	29900000169180501018	4206
3444	29900000169180601015	4206
3445	29900000169180701012	4206
3446	29900000169180801019	4206
3447	29900000169180901016	4206
3448	29900000169181001014	4206
3449	29900000169181101011	4206
3450	29900000169181201018	4206
3451	29900000169181301015	4206
3452	29900000169181401012	4206
3453	29900000169181501019	4206
3454	29900000169181601016	4206
3455	29900000169181701013	4206
3456	29900000169194601016	4207
3457	29900000169194701013	4207
3458	29900000169194801010	4207
3459	29900000169194901017	4207
3460	29900000169195001015	4207
3461	29900000169195101012	4207
3462	29900000169195201019	4207
3463	29900000169195301016	4207
3464	29900000169195401013	4207
3465	29900000169195501010	4207
3466	29900000169195601017	4207
3467	29900000169195701014	4207
3468	29900000169195801011	4207
3469	29900000169195901018	4207
3470	29900000169196001016	4207
3471	29900000169196101013	4207
3472	29900000169196201010	4207
3473	29900000169196301017	4207
3474	29900000169196401014	4207
3475	29900000169196501011	4207
3476	29900000169196601018	4207
3477	29900000169196701015	4207
3478	29900000169177401011	4208
3479	29900000169177501018	4208
3480	29900000169177601015	4208
3481	29900000169177701012	4208
3482	29900000169177801019	4208
3483	29900000169177901016	4208
3484	29900000169178001014	4208
3485	29870000012144101015	4203
3486	29870000012145201013	4209
3487	29870000012145301010	4209
3488	29870000012145401017	4209
3489	29870000012145501014	4209
3490	29870000012147801017	4210
3491	29870000012147901014	4211
3492	29870000012148301013	4212
3493	29870000012148401010	4212
3494	29870000012148501017	4213
3495	29870000012148601014	4213
3496	29870000012148701011	4214
3497	29870000012148901015	4215
3498	29870000012149001013	4215
3499	29870000012149101010	4215
3500	29870000012149201017	4215
3501	29870000012149301014	4215
3502	29870000012149401011	4216
3503	29870000012149501018	4216
\.


--
-- Data for Name: codigos_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.codigos_items (id, codigo_barras, item, resultado, fecha_actualizacion) FROM stdin;
\.


--
-- Data for Name: configuracion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.configuracion (id, clave, valor, descripcion, fecha_actualizacion) FROM stdin;
22	ruta_clp		Ruta al archivo CLP	2025-06-28 13:22:47.861141
2	url_actualizaciones	http://localhost:8000/updates	URL para actualizaciones	2025-06-28 12:04:39.328707
23	ruta_historico		Ruta al archivo histrico	2025-06-28 13:22:47.861141
1	version_actual	1.0.0	Versin actual de la aplicacin	2025-06-28 12:04:39.328707
4	max_intentos_login	3	Mximo nmero de intentos de login	2025-06-28 12:04:39.328707
19	contenedor	C:/Users/bost2/OneDrive/Escritorio/Libro1.xlsx	Configuracin de contenedor	2025-06-28 13:16:17.651216
20	modelos	C:/Users/bost2/OneDrive/Escritorio/MODELOS CUMPLIENDO (004).xlsx	Configuracin de modelos	2025-06-28 13:16:27.81417
3	auto_actualizar	true	Habilitar actualizaciones automticas	2025-06-28 12:04:39.328707
\.


--
-- Data for Name: connections; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.connections (id, url_path, user_id, name, db_name, db_host, db_port, db_user, db_pass, db_connection_timeout, db_schema_filter, db_ssl, ssl_certificate, ssl_client_certificate, ssl_client_certificate_key, ssl_reject_unauthorized, db_conn, db_watch_shema, disable_realtime, prgl_url, prgl_params, type, is_state_db, on_mount_ts, on_mount_ts_disabled, info, table_options, config, created, last_updated) FROM stdin;
98b20426-f01b-4186-bde2-6b426b14e0c1	\N	\N	Prostgles UI state	Escaner	localhost	5432	postgres	ubuntu	\N	\N	disable	\N	\N	\N	\N	postgres://postgres:ubuntu@localhost:5432/Escaner?sslmode=disable	t	f	\N	\N	Connection URI	t	\N	\N	{"canCreateDb": true}	\N	\N	2025-06-30 10:04:03.715276	1751299443550
\.


--
-- Data for Name: consultas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.consultas (id, usuario, codigo_barras, item_id, fecha_hora, resultado) FROM stdin;
1	admin	29860000298102301012	744	2025-07-07 15:14:58.614407	NO CUMPLE
2	admin	29860000298104301014	959	2025-07-07 15:15:59.922285	NO CUMPLE
3	admin	29860000298104401011	959	2025-07-07 15:16:08.072458	NO CUMPLE
4	admin	29860000298111201011	486	2025-07-07 16:47:13.425538	NO CUMPLE
5	admin	29860000298102301012	744	2025-07-07 17:14:21.213935	NO CUMPLE
6	admin	29860000298102301012	744	2025-07-07 17:29:44.046254	NO CUMPLE
7	admin	29860000298154001018	4129	2025-07-08 09:13:47.765708	\N
8	admin	29860000298099201014	3817	2025-07-08 09:42:21.727854	\N
9	admin	29860000298122301016	3845	2025-07-08 09:43:49.036492	\N
10	admin	29860000298124701016	3865	2025-07-08 09:43:55.39982	\N
11	admin	29860000298194101013	1886	2025-07-08 09:44:05.504355	CUMPLE
12	admin	29860000298194101013	1886	2025-07-08 09:53:58.008996	CUMPLE
13	admin	29860000298124701016	3865	2025-07-08 09:55:59.132447	\N
14	admin	29860000298124701016	3865	2025-07-08 09:56:02.50071	\N
15	admin	29860000298102301012	744	2025-07-10 17:50:31.321271	NO CUMPLE
16	admin	29860000298102301012	744	2025-07-11 09:57:45.226055	NO CUMPLE
17	admin	29860000298102301012	744	2025-07-11 12:48:36.569422	NO CUMPLE
18	admin	29860000298102301012	744	2025-07-14 12:11:13.275969	NO CUMPLE
19	admin	29860000298102301012	744	2025-07-14 12:23:55.776794	NO CUMPLE
20	admin	29860000298102301012	744	2025-07-14 12:25:51.489729	NO CUMPLE
\.


--
-- Data for Name: credential_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.credential_types (id) FROM stdin;
s3
\.


--
-- Data for Name: credentials; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.credentials (id, name, user_id, type, key_id, key_secret, bucket, region) FROM stdin;
\.


--
-- Data for Name: database_config_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.database_config_logs (id, on_mount_logs, table_config_logs, on_run_logs) FROM stdin;
\.


--
-- Data for Name: database_configs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.database_configs (id, db_name, db_host, db_port, rest_api_enabled, sync_users, table_config, table_config_ts, table_config_ts_disabled, file_table_config, backups_config) FROM stdin;
1	Escaner	localhost	5432	f	f	\N	\N	\N	\N	\N
\.


--
-- Data for Name: database_stats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.database_stats (database_config_id) FROM stdin;
\.


--
-- Data for Name: global_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.global_settings (id, allowed_origin, allowed_ips, allowed_ips_enabled, trust_proxy, enable_logs, session_max_age_days, magic_link_validity_days, updated_by, updated_at, pass_process_env_vars_to_server_side_functions, login_rate_limit_enabled, login_rate_limit, auth_providers, "tableConfig", prostgles_registration) FROM stdin;
1	*	{::ffff:127.0.0.1/128}	f	f	f	14	1	app	2025-06-30 10:04:03.438791	f	t	{"groupBy": "ip", "maxAttemptsPerHour": 5}	\N	{"logs": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "sid": "TEXT", "data": "JSONB", "type": "TEXT", "error": "JSON", "command": "TEXT", "created": "TIMESTAMP DEFAULT NOW()", "tx_info": "JSONB", "duration": "NUMERIC", "has_error": "BOOLEAN", "socket_id": "TEXT", "table_name": "TEXT", "connection_id": "UUID"}}, "links": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "w1_id": "UUID NOT NULL REFERENCES windows(id)  ON DELETE CASCADE", "w2_id": "UUID NOT NULL REFERENCES windows(id)  ON DELETE CASCADE", "closed": "BOOLEAN DEFAULT FALSE", "created": "TIMESTAMP DEFAULT NOW()", "deleted": "BOOLEAN DEFAULT FALSE", "options": {"jsonbSchema": {"oneOfType": [{"type": {"enum": ["table"]}, "colorArr": {"type": "number[]", "optional": true}, "tablePath": {"optional": false, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "Table path from w1.table_name to w2.table_name"}}, {"sql": {"type": "string", "optional": true, "description": "Defined if chart links to SQL statement"}, "type": {"enum": ["map"]}, "columns": {"arrayOfType": {"name": {"type": "string", "description": "Geometry/Geography column"}, "colorArr": "number[]"}}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}, "mapIcons": {"optional": true, "oneOfType": [{"type": {"enum": ["fixed"]}, "iconPath": "string"}, {"type": {"enum": ["conditional"]}, "columnName": "string", "conditions": {"arrayOfType": {"value": "any", "iconPath": "string"}}}]}, "dataSource": {"optional": true, "oneOfType": [{"sql": "string", "type": {"enum": ["sql"], "description": "Show data from an SQL query within an editor. Will not reflect latest changes to that query (must be re-added)"}, "withStatement": "string"}, {"type": {"enum": ["table"], "description": "Shows data from an opened table window. Any filters from that table will apply to the chart as well"}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}}, {"type": {"enum": ["local-table"], "description": "Shows data from postgres table not connected to any window (w1_id === w2_id === current chart window). Custom filters can be added"}, "localTableName": {"type": "string"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}]}, "mapShowText": {"type": {"columnName": {"type": "string"}}, "optional": true}, "mapColorMode": {"optional": true, "oneOfType": [{"type": {"enum": ["fixed"]}, "colorArr": "number[]"}, {"max": "number", "min": "number", "type": {"enum": ["scale"]}, "columnName": "string", "maxColorArr": "number[]", "minColorArr": "number[]"}, {"type": {"enum": ["conditional"]}, "columnName": "string", "conditions": {"arrayOfType": {"value": "any", "colorArr": "number[]"}}}]}, "osmLayerQuery": {"type": "string", "optional": true, "description": "If provided then this is a OSM layer (w1_id === w2_id === current chart window)"}, "localTableName": {"type": "string", "optional": true, "description": "If provided then this is a local layer (w1_id === w2_id === current chart window)"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}, {"sql": {"type": "string", "optional": true, "description": "Defined if chart links to SQL statement"}, "type": {"enum": ["timechart"]}, "columns": {"arrayOfType": {"name": {"type": "string", "description": "Date column"}, "colorArr": "number[]", "statType": {"type": {"funcName": {"enum": ["$min", "$max", "$countAll", "$avg", "$sum"]}, "numericColumn": "string"}, "optional": true}}}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}, "dataSource": {"optional": true, "oneOfType": [{"sql": "string", "type": {"enum": ["sql"], "description": "Show data from an SQL query within an editor. Will not reflect latest changes to that query (must be re-added)"}, "withStatement": "string"}, {"type": {"enum": ["table"], "description": "Shows data from an opened table window. Any filters from that table will apply to the chart as well"}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}}, {"type": {"enum": ["local-table"], "description": "Shows data from postgres table not connected to any window (w1_id === w2_id === current chart window). Custom filters can be added"}, "localTableName": {"type": "string"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}]}, "otherColumns": {"optional": true, "arrayOfType": {"name": "string", "label": {"type": "string", "optional": true}, "udt_name": "string"}}, "groupByColumn": {"type": "string", "optional": true, "description": "Used by timechart"}, "localTableName": {"type": "string", "optional": true, "description": "If provided then this is a local layer (w1_id === w2_id === current chart window)"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}]}}, "user_id": "UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE", "disabled": "boolean", "last_updated": "BIGINT NOT NULL", "workspace_id": "UUID REFERENCES workspaces(id) ON DELETE SET NULL"}}, "stats": {"columns": {"cmd": {"info": {"hint": "Command with all its arguments as a string"}, "sqlDefinition": "TEXT"}, "cpu": {"info": {"hint": "CPU Utilisation. CPU time used divided by the time the process has been running. It will not add up to 100% unless you are lucky"}, "sqlDefinition": "NUMERIC"}, "mem": {"info": {"hint": "Ratio of the process's resident set size  to the physical memory on the machine, expressed as a percentage"}, "sqlDefinition": "NUMERIC"}, "mhz": {"info": {"hint": "Core MHz value"}, "sqlDefinition": "TEXT"}, "pid": "INTEGER NOT NULL", "datid": "INTEGER", "query": {"info": {"hint": "Text of this backend's most recent query. If state is active this field shows the currently executing query. In all other states, it shows the last query that was executed. By default the query text is truncated at 1024 bytes; this value can be changed via the parameter track_activity_query_size."}, "sqlDefinition": "TEXT"}, "state": {"info": {"hint": "Current overall state of this backend. Possible values are: active: The backend is executing a query. idle: The backend is waiting for a new client command. idle in transaction: The backend is in a transaction, but is not currently executing a query. idle in transaction (aborted): This state is similar to idle in transaction, except one of the statements in the transaction caused an error. fastpath function call: The backend is executing a fast-path function. disabled: This state is reported if track_activities is disabled in this backend."}, "sqlDefinition": "TEXT"}, "datname": "TEXT", "usename": {"info": {"hint": "Name of the user logged into this backend"}, "sqlDefinition": "TEXT"}, "usesysid": "INTEGER", "memPretty": {"info": {"hint": "mem value as string"}, "sqlDefinition": "TEXT"}, "blocked_by": {"info": {"hint": "Process ID(s) of the sessions that are blocking the server process with the specified process ID from acquiring a lock. One server process blocks another if it either holds a lock that conflicts with the blocked process's lock request (hard block), or is waiting for a lock that would conflict with the blocked process's lock request and is ahead of it in the wait queue (soft block). When using parallel queries the result always lists client-visible process IDs (that is, pg_backend_pid results) even if the actual lock is held or awaited by a child worker process. As a result of that, there may be duplicated PIDs in the result. Also note that when a prepared transaction holds a conflicting lock, it will be represented by a zero process ID."}, "sqlDefinition": "INTEGER[]"}, "wait_event": {"info": {"hint": "Wait event name if backend is currently waiting, otherwise NULL. See Table 28.5 through Table 28.13."}, "sqlDefinition": "TEXT"}, "xact_start": {"info": {"hint": "Time when this process' current transaction was started, or null if no transaction is active. If the current query is the first of its transaction, this column is equal to the query_start column."}, "sqlDefinition": "TEXT"}, "backend_xid": {"info": {"hint": "Top-level transaction identifier of this backend, if any."}, "sqlDefinition": "TEXT"}, "client_addr": {"info": {"hint": "IP address of the client connected to this backend. If this field is null, it indicates either that the client is connected via a Unix socket on the server machine or that this is an internal process such as autovacuum."}, "sqlDefinition": "TEXT"}, "client_port": {"info": {"hint": "TCP port number that the client is using for communication with this backend, or -1 if a Unix socket is used. If this field is null, it indicates that this is an internal server process."}, "sqlDefinition": "INTEGER"}, "query_start": {"info": {"hint": "Time when the currently active query was started, or if state is not active, when the last query was started"}, "sqlDefinition": "TIMESTAMP"}, "backend_type": {"info": {"hint": "Type of current backend. Possible types are autovacuum launcher, autovacuum worker, logical replication launcher, logical replication worker, parallel worker, background writer, client backend, checkpointer, archiver, startup, walreceiver, walsender and walwriter. In addition, background workers registered by extensions may have additional types."}, "sqlDefinition": "TEXT"}, "backend_xmin": {"info": {"hint": "The current backend's xmin horizon."}, "sqlDefinition": "TEXT"}, "state_change": {"info": {"hint": "Time when the state was last changed"}, "sqlDefinition": "TEXT"}, "backend_start": {"info": {"hint": "Time when this process was started. For client backends, this is the time the client connected to the server."}, "sqlDefinition": "TEXT"}, "connection_id": "UUID NOT NULL REFERENCES connections(id) ON DELETE CASCADE", "id_query_hash": {"info": {"hint": "Computed query identifier (md5(pid || query)) used in stopping queries"}, "sqlDefinition": "TEXT"}, "blocked_by_num": "INTEGER NOT NULL DEFAULT 0", "client_hostname": {"info": {"hint": "Host name of the connected client, as reported by a reverse DNS lookup of client_addr. This field will only be non-null for IP connections, and only when log_hostname is enabled."}, "sqlDefinition": "TEXT"}, "wait_event_type": {"info": {"hint": "The type of event for which the backend is waiting, if any; otherwise NULL. See Table 28.4."}, "sqlDefinition": "TEXT"}, "application_name": {"info": {"hint": "Name of the application that is connected to this backend"}, "sqlDefinition": "TEXT"}}, "constraints": {"stats_pkey": "PRIMARY KEY(pid, connection_id)"}}, "users": {"columns": {"id": {"sqlDefinition": "UUID PRIMARY KEY DEFAULT gen_random_uuid()"}, "2fa": {"nullable": true, "jsonbSchemaType": {"secret": {"type": "string"}, "enabled": {"type": "boolean"}, "recoveryCode": {"type": "string"}}}, "name": {"info": {"hint": "Display name, if empty username will be shown"}, "sqlDefinition": "TEXT"}, "type": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'default' REFERENCES user_types (id)"}, "email": {"sqlDefinition": "TEXT"}, "status": {"info": {"hint": "Only active users can access the system"}, "sqlDefinition": "TEXT NOT NULL DEFAULT 'active' REFERENCES user_statuses (id)"}, "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "options": {"nullable": true, "jsonbSchemaType": {"theme": {"enum": ["dark", "light", "from-system"], "optional": true}, "showStateDB": {"type": "boolean", "optional": true, "description": "Show the prostgles database in the connections list"}, "viewedSQLTips": {"type": "boolean", "optional": true, "description": "Will hide SQL tips if true"}, "viewedAccessInfo": {"type": "boolean", "optional": true, "description": "Will hide passwordless user tips if true"}, "hideNonSSLWarning": {"type": "boolean", "optional": true, "description": "Hides the top warning when accessing the website over an insecure connection (non-HTTPS)"}}}, "password": {"info": {"hint": "Hashed with the user id on insert/update"}, "sqlDefinition": "TEXT NOT NULL"}, "username": {"sqlDefinition": "TEXT NOT NULL UNIQUE CHECK(length(username) > 0)"}, "last_updated": {"sqlDefinition": "BIGINT DEFAULT EXTRACT(EPOCH FROM NOW()) * 1000"}, "registration": {"nullable": true, "jsonbSchema": {"oneOfType": [{"type": {"enum": ["password-w-email-confirmation"]}, "email_confirmation": {"oneOfType": [{"date": "Date", "status": {"enum": ["confirmed"]}}, {"date": "Date", "status": {"enum": ["pending"]}, "confirmation_code": {"type": "string"}}]}}, {"date": "Date", "type": {"enum": ["magic-link"]}, "used_on": {"type": "Date", "optional": true}, "otp_code": {"type": "string"}}, {"type": {"enum": ["OAuth"]}, "profile": "any", "user_id": "string", "provider": {"enum": ["google", "facebook", "github", "microsoft", "customOAuth"], "description": "OAuth provider name. E.g.: google, github"}}]}}, "auth_provider": {"info": {"hint": "OAuth provider name. E.g.: google, github"}, "sqlDefinition": "TEXT"}, "has_2fa_enabled": "BOOLEAN GENERATED ALWAYS AS ( (\\"2fa\\"->>'enabled')::BOOLEAN ) STORED", "passwordless_admin": {"info": {"hint": "If true and status is active: enables passwordless access for default install. First connected client will have perpetual admin access and no other users are allowed "}, "sqlDefinition": "BOOLEAN"}, "auth_provider_profile": {"info": {"hint": "OAuth provider profile data"}, "sqlDefinition": "JSONB"}, "auth_provider_user_id": {"info": {"hint": "User id"}, "sqlDefinition": "TEXT"}}, "indexes": {"Only one passwordless_admin admin account allowed": {"where": "passwordless_admin = true", "unique": true, "columns": "passwordless_admin"}}, "triggers": {"atLeastOneActiveAdmin": {"type": "after", "query": "\\n          BEGIN\\n            IF NOT EXISTS(SELECT * FROM users WHERE type = 'admin' AND status = 'active') THEN\\n              RAISE EXCEPTION 'Must have at least one active admin user';\\n            END IF;\\n\\n            RETURN NULL;\\n          END;\\n        ", "actions": ["delete", "update"], "forEach": "statement"}}, "constraints": {"passwordless_admin type AND username CHECK": "CHECK(COALESCE(passwordless_admin, false) = FALSE OR type = 'admin' AND username = 'passwordless_admin')"}}, "alerts": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "data": "JSONB", "title": "TEXT", "created": "TIMESTAMP DEFAULT NOW()", "message": "TEXT", "section": {"enum": ["access_control", "backups", "table_config", "details", "status", "methods", "file_storage", "API"], "nullable": true}, "severity": {"enum": ["info", "warning", "error"]}, "connection_id": "UUID REFERENCES connections(id) ON DELETE SET NULL", "database_config_id": "INTEGER REFERENCES database_configs(id) ON DELETE SET NULL"}}, "backups": {"columns": {"id": {"info": {"hint": "Format: dbname_datetime_uuid"}, "sqlDefinition": "TEXT PRIMARY KEY DEFAULT gen_random_uuid()"}, "status": {"jsonbSchema": {"oneOfType": [{"ok": {"type": "string"}}, {"err": {"type": "string"}}, {"loading": {"type": {"total": {"type": "number", "optional": true}, "loaded": {"type": "number"}}, "optional": true}}]}}, "created": {"sqlDefinition": "TIMESTAMP NOT NULL DEFAULT NOW()"}, "details": {"sqlDefinition": "JSONB"}, "options": {"jsonbSchema": {"oneOfType": [{"clean": {"type": "boolean"}, "command": {"enum": ["pg_dumpall"]}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "rolesOnly": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "globalsOnly": {"type": "boolean", "optional": true}}, {"clean": {"type": "boolean", "optional": true}, "create": {"type": "boolean", "optional": true}, "format": {"enum": ["p", "t", "c"]}, "command": {"enum": ["pg_dump"]}, "noOwner": {"type": "boolean", "optional": true}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "numberOfJobs": {"type": "integer", "optional": true}, "excludeSchema": {"type": "string", "optional": true}, "compressionLevel": {"type": "integer", "optional": true}}]}}, "uploaded": {"sqlDefinition": "TIMESTAMP"}, "dump_logs": {"sqlDefinition": "TEXT"}, "initiator": {"sqlDefinition": "TEXT"}, "destination": {"enum": ["Local", "Cloud", "None (temp stream)"], "nullable": false}, "restore_end": {"sqlDefinition": "TIMESTAMP"}, "sizeInBytes": {"label": "Backup file size", "sqlDefinition": "BIGINT"}, "content_type": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'application/gzip'"}, "dump_command": {"sqlDefinition": "TEXT NOT NULL"}, "last_updated": {"sqlDefinition": "TIMESTAMP NOT NULL DEFAULT NOW()"}, "restore_logs": {"sqlDefinition": "TEXT"}, "connection_id": {"info": {"hint": "If null then connection was deleted"}, "sqlDefinition": "UUID REFERENCES connections(id) ON DELETE SET NULL"}, "credential_id": {"info": {"hint": "If null then uploaded locally"}, "sqlDefinition": "INTEGER REFERENCES credentials(id) "}, "dbSizeInBytes": {"label": "Database size on disk", "sqlDefinition": "BIGINT NOT NULL"}, "restore_start": {"sqlDefinition": "TIMESTAMP"}, "local_filepath": {"sqlDefinition": "TEXT"}, "restore_status": {"nullable": true, "jsonbSchema": {"oneOfType": [{"ok": {"type": "string"}}, {"err": {"type": "string"}}, {"loading": {"type": {"total": {"type": "number"}, "loaded": {"type": "number"}}}}]}}, "restore_command": {"sqlDefinition": "TEXT"}, "restore_options": {"defaultValue": "{ \\"clean\\": true, \\"format\\": \\"c\\", \\"command\\": \\"pg_restore\\" }", "jsonbSchemaType": {"clean": {"type": "boolean"}, "create": {"type": "boolean", "optional": true}, "format": {"enum": ["p", "t", "c"]}, "command": {"enum": ["pg_restore", "psql"]}, "noOwner": {"type": "boolean", "optional": true}, "dataOnly": {"type": "boolean", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "newDbName": {"type": "string", "optional": true}, "numberOfJobs": {"type": "integer", "optional": true}, "excludeSchema": {"type": "string", "optional": true}}}, "connection_details": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'unknown connection' "}}}, "windows": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "sql": "TEXT NOT NULL DEFAULT ''", "name": "TEXT", "sort": "JSONB DEFAULT '[]'::jsonb", "type": "TEXT CHECK(type IN ('map', 'sql', 'table', 'timechart', 'card', 'method'))", "limit": "INTEGER DEFAULT 1000 CHECK(\\"limit\\" > -1 AND \\"limit\\" < 100000)", "closed": "BOOLEAN DEFAULT FALSE", "filter": "JSONB NOT NULL DEFAULT '[]'::jsonb", "having": "JSONB NOT NULL DEFAULT '[]'::jsonb", "columns": "JSONB", "created": "TIMESTAMP NOT NULL DEFAULT NOW()", "deleted": "BOOLEAN DEFAULT FALSE CHECK(NOT (type = 'sql' AND deleted = TRUE AND (options->>'sqlWasSaved')::boolean = true))", "options": "JSONB NOT NULL DEFAULT '{}'::jsonb", "user_id": "UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE", "minimised": {"info": {"hint": "Used for attached charts to hide them"}, "sqlDefinition": "BOOLEAN DEFAULT FALSE"}, "show_menu": "BOOLEAN DEFAULT FALSE", "table_oid": "INTEGER", "fullscreen": "BOOLEAN DEFAULT TRUE", "table_name": "TEXT", "method_name": "TEXT", "sql_options": {"defaultValue": {"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}, "jsonbSchemaType": {"theme": {"enum": ["vs", "vs-dark", "hc-black", "hc-light"], "optional": true}, "minimap": {"type": {"enabled": {"type": "boolean"}}, "optional": true, "description": "Shows a vertical code minimap to the right"}, "tabSize": {"type": "integer", "optional": true}, "renderMode": {"enum": ["table", "csv", "JSON"], "optional": true, "description": "Show query results in a table or a JSON"}, "lineNumbers": {"enum": ["on", "off"], "optional": true}, "executeOptions": {"enum": ["full", "block", "smallest-block"], "optional": true, "description": "Behaviour of execute (ALT + E). Defaults to 'block' \\nfull = run entire sql   \\nblock = run code block where the cursor is"}, "maxCharsPerCell": {"type": "integer", "optional": true, "description": "Defaults to 1000. Maximum number of characters to display for each cell. Useful in improving performance"}, "errorMessageDisplay": {"enum": ["tooltip", "bottom", "both"], "optional": true, "description": "Error display locations. Defaults to 'both' \\ntooltip = show within tooltip only   \\nbottom = show in bottom control bar only   \\nboth = show in both locations"}, "expandSuggestionDocs": {"type": "boolean", "optional": true, "description": "Toggle suggestions documentation tab. Requires page refresh. Enabled by default"}, "showRunningQueryStats": {"type": "boolean", "optional": true, "description": "(Experimental) Display running query stats (CPU and Memory usage) in the bottom bar"}, "acceptSuggestionOnEnter": {"enum": ["on", "smart", "off"], "optional": true, "description": "Insert suggestions on Enter. Tab is the default key"}}}, "last_updated": "BIGINT NOT NULL", "selected_sql": "TEXT NOT NULL DEFAULT ''", "workspace_id": "UUID REFERENCES workspaces(id) ON DELETE SET NULL", "nested_tables": "JSONB", "function_options": {"nullable": true, "jsonbSchemaType": {"showDefinition": {"type": "boolean", "optional": true, "description": "Show the function definition"}}}, "parent_window_id": {"info": {"hint": "If defined then this is a chart for another window and will be rendered within that parent window"}, "sqlDefinition": "UUID REFERENCES windows(id) ON DELETE CASCADE"}}}, "sessions": {"columns": {"id": "TEXT UNIQUE NOT NULL", "name": "TEXT", "type": "TEXT NOT NULL REFERENCES session_types", "active": "BOOLEAN DEFAULT TRUE", "id_num": "SERIAL PRIMARY KEY", "created": "TIMESTAMP DEFAULT NOW()", "expires": "BIGINT NOT NULL", "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "is_mobile": "BOOLEAN DEFAULT FALSE", "last_used": "TIMESTAMP DEFAULT NOW()", "socket_id": "TEXT", "user_type": "TEXT NOT NULL", "ip_address": "INET NOT NULL", "project_id": "TEXT", "user_agent": "TEXT", "is_connected": "BOOLEAN DEFAULT FALSE"}}, "llm_chats": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "name": "TEXT NOT NULL DEFAULT 'New chat'", "created": "TIMESTAMP DEFAULT NOW()", "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "llm_prompt_id": "INTEGER REFERENCES llm_prompts(id) ON DELETE SET NULL", "disabled_until": {"info": {"hint": "If set then chat is disabled until this time"}, "sqlDefinition": "TIMESTAMPTZ"}, "disabled_message": {"info": {"hint": "Message to show when chat is disabled"}, "sqlDefinition": "TEXT"}, "llm_credential_id": "INTEGER REFERENCES llm_credentials(id) ON DELETE SET NULL"}}, "user_types": {"triggers": {"atLeastOneAdminAndPublic": {"type": "after", "query": " \\n          BEGIN\\n            IF NOT EXISTS(SELECT * FROM user_types WHERE id = 'admin') \\n              OR NOT EXISTS(SELECT * FROM user_types WHERE id = 'public')\\n            THEN\\n              RAISE EXCEPTION 'admin and public user types cannot be deleted/modified';\\n            END IF;\\n  \\n            RETURN NULL;\\n          END;\\n        ", "actions": ["delete", "update"], "forEach": "statement"}}, "isLookupTable": {"values": {"admin": {"en": "Highest access level"}, "public": {"en": "Public user. Account created on login and deleted on logout"}, "default": {}}}}, "workspaces": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "icon": "TEXT", "name": "TEXT NOT NULL DEFAULT 'default workspace'", "layout": "JSONB", "created": "TIMESTAMP DEFAULT NOW()", "deleted": "BOOLEAN NOT NULL DEFAULT FALSE", "options": {"defaultValue": {"hideCounts": false, "pinnedMenu": true, "tableListSortBy": "extraInfo", "tableListEndInfo": "size", "defaultLayoutType": "tab"}, "jsonbSchemaType": {"hideCounts": {"type": "boolean", "optional": true}, "pinnedMenu": {"type": "boolean", "optional": true}, "pinnedMenuWidth": {"type": "number", "optional": true}, "tableListSortBy": {"enum": ["name", "extraInfo"], "optional": true}, "showAllMyQueries": {"type": "boolean", "optional": true}, "tableListEndInfo": {"enum": ["none", "count", "size"], "optional": true}, "defaultLayoutType": {"enum": ["row", "tab", "col"], "optional": true}}}, "user_id": "UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE", "url_path": "TEXT", "last_used": "TIMESTAMP NOT NULL DEFAULT now()", "published": {"info": {"hint": "If true then this workspace can be shared with other users through Access Control"}, "sqlDefinition": "BOOLEAN NOT NULL DEFAULT FALSE, CHECK(parent_workspace_id IS NULL OR published = FALSE)"}, "active_row": "JSONB DEFAULT '{}'::jsonb", "last_updated": "BIGINT NOT NULL", "publish_mode": "TEXT REFERENCES workspace_publish_modes ", "connection_id": "UUID NOT NULL REFERENCES connections(id)  ON DELETE CASCADE", "parent_workspace_id": "UUID REFERENCES workspaces(id) ON DELETE SET NULL"}, "constraints": {"unique_url_path": "UNIQUE(url_path)", "unique_name_per_user_perCon": "UNIQUE(connection_id, user_id, name)"}}, "connections": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "info": {"nullable": true, "jsonbSchemaType": {"canCreateDb": {"type": "boolean", "optional": true, "description": "True if postgres user is allowed to create databases. Never gets updated"}}}, "name": "TEXT NOT NULL CHECK(LENGTH(name) > 0)", "type": {"enum": ["Standard", "Connection URI", "Prostgles"], "nullable": false}, "config": {"nullable": true, "jsonbSchemaType": {"path": "string", "enabled": "boolean"}}, "db_ssl": {"enum": ["disable", "allow", "prefer", "require", "verify-ca", "verify-full"], "nullable": false, "defaultValue": "disable"}, "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "db_conn": {"sqlDefinition": "TEXT DEFAULT ''"}, "db_host": "TEXT NOT NULL DEFAULT 'localhost'", "db_name": "TEXT NOT NULL CHECK(LENGTH(db_name) > 0)", "db_pass": "TEXT DEFAULT ''", "db_port": "INTEGER NOT NULL DEFAULT 5432", "db_user": "TEXT NOT NULL DEFAULT ''", "user_id": "UUID REFERENCES users(id) ON DELETE CASCADE", "prgl_url": {"sqlDefinition": "TEXT"}, "url_path": {"info": {"hint": "URL path to be used instead of the connection uuid"}, "sqlDefinition": "TEXT CHECK(LENGTH(url_path) > 0 AND url_path ~ '^[a-z0-9-]+$')"}, "is_state_db": {"info": {"hint": "If true then this DB is used to run the dashboard"}, "sqlDefinition": "BOOLEAN"}, "on_mount_ts": {"info": {"hint": "On mount typescript function. Must export const onMount"}, "sqlDefinition": "TEXT"}, "prgl_params": {"sqlDefinition": "JSONB"}, "last_updated": {"sqlDefinition": "BIGINT NOT NULL DEFAULT 0"}, "table_options": {"nullable": true, "jsonbSchema": {"record": {"values": {"type": {"icon": {"type": "string", "optional": true}}}, "partial": true}}}, "db_watch_shema": {"sqlDefinition": "BOOLEAN DEFAULT TRUE"}, "ssl_certificate": {"sqlDefinition": "TEXT"}, "db_schema_filter": {"nullable": true, "jsonbSchema": {"oneOf": [{"record": {"values": {"enum": [1]}}}, {"record": {"values": {"enum": [0]}}}]}}, "disable_realtime": {"info": {"hint": "If true then subscriptions and syncs will not work. Used to ensure prostgles schema is not created and nothing is changed in the database"}, "sqlDefinition": "BOOLEAN DEFAULT FALSE"}, "on_mount_ts_disabled": {"info": {"hint": "If true then On mount typescript will not be executed"}, "sqlDefinition": "BOOLEAN"}, "db_connection_timeout": "INTEGER CHECK(db_connection_timeout > 0)", "ssl_client_certificate": {"sqlDefinition": "TEXT"}, "ssl_reject_unauthorized": {"info": {"hint": "If true, the server certificate is verified against the list of supplied CAs. \\nAn error event is emitted if verification fails"}, "sqlDefinition": "BOOLEAN"}, "ssl_client_certificate_key": {"sqlDefinition": "TEXT"}}, "constraints": {"uniqueConName": "UNIQUE(name, user_id)", "database_config_fkey": "FOREIGN KEY (db_name, db_host, db_port) REFERENCES database_configs( db_name, db_host, db_port )", "Check connection type": "CHECK (\\n            type IN ('Standard', 'Connection URI', 'Prostgles') \\n            AND (type <> 'Connection URI' OR length(db_conn) > 1) \\n            AND (type <> 'Standard' OR length(db_host) > 1) \\n            AND (type <> 'Prostgles' OR length(prgl_url) > 0)\\n          )", "unique_connection_url_path": "UNIQUE(url_path)"}}, "credentials": {"columns": {"id": "SERIAL PRIMARY KEY", "name": "TEXT NOT NULL DEFAULT ''", "type": "TEXT NOT NULL REFERENCES credential_types(id) DEFAULT 's3'", "bucket": "TEXT", "key_id": "TEXT NOT NULL", "region": "TEXT", "user_id": "UUID REFERENCES users(id) ON DELETE SET NULL", "key_secret": "TEXT NOT NULL"}, "constraints": {"Bucket or Region missing": "CHECK(type <> 's3' OR (bucket IS NOT NULL AND region IS NOT NULL))"}}, "llm_prompts": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "name": "TEXT NOT NULL DEFAULT 'New prompt'", "prompt": "TEXT NOT NULL CHECK(LENGTH(btrim(prompt)) > 0)", "created": "TIMESTAMP DEFAULT NOW()", "user_id": "UUID REFERENCES users(id) ON DELETE SET NULL", "description": "TEXT DEFAULT ''"}, "indexes": {"unique_llm_prompt_name": {"unique": true, "columns": "name, user_id"}}}, "magic_links": {"columns": {"id": "TEXT PRIMARY KEY DEFAULT gen_random_uuid()", "expires": "BIGINT NOT NULL", "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "magic_link": "TEXT", "magic_link_used": "TIMESTAMP", "session_expires": "BIGINT NOT NULL DEFAULT 0"}}, "llm_messages": {"columns": {"id": "int8 PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "chat_id": "INTEGER NOT NULL REFERENCES llm_chats(id) ON DELETE CASCADE", "created": "TIMESTAMP DEFAULT NOW()", "message": "TEXT NOT NULL", "user_id": "UUID REFERENCES users(id) ON DELETE CASCADE"}}, "session_types": {"isLookupTable": {"values": {"web": {}, "mobile": {}, "api_token": {}}}}, "user_statuses": {"isLookupTable": {"values": {"active": {}, "disabled": {}}}}, "access_control": {"columns": {"id": "SERIAL PRIMARY KEY", "name": "TEXT", "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "database_id": "INTEGER NOT NULL REFERENCES database_configs(id) ON DELETE CASCADE", "dbPermissions": {"info": {"hint": "Permission types and rules for this (connection_id) database"}, "jsonbSchema": {"oneOfType": [{"type": {"enum": ["Run SQL"], "description": "Allows complete access to the database"}, "allowSQL": {"type": "boolean", "optional": true}}, {"type": {"enum": ["All views/tables"], "description": "Custom access (View/Edit/Remove) to all tables"}, "allowAllTables": {"type": "string[]", "allowedValues": ["select", "insert", "update", "delete"]}}, {"type": {"enum": ["Custom"], "description": "Fine grained access to specific tables"}, "customTables": {"arrayOfType": {"sync": {"type": {"throttle": {"type": "integer", "optional": true}, "id_fields": {"type": "string[]"}, "allow_delete": {"type": "boolean", "optional": true}, "synced_field": {"type": "string"}}, "optional": true}, "delete": {"oneOf": ["boolean", {"type": {"filterFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "forcedFilterDetailed": {"type": "any", "optional": true}}}], "optional": true}, "insert": {"oneOf": ["boolean", {"type": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "forcedDataDetail": {"type": "any[]", "optional": true}, "checkFilterDetailed": {"type": "any", "optional": true}}}], "optional": true}, "select": {"oneOf": ["boolean", {"type": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "subscribe": {"type": {"throttle": {"type": "integer", "optional": true}}, "optional": true}, "filterFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "orderByFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "forcedFilterDetailed": {"type": "any", "optional": true}}}], "optional": true, "description": "Allows viewing data"}, "update": {"oneOf": ["boolean", {"type": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "filterFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "dynamicFields": {"optional": true, "arrayOfType": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "filterDetailed": "any"}}, "orderByFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "forcedDataDetail": {"type": "any[]", "optional": true}, "checkFilterDetailed": {"type": "any", "optional": true}, "forcedFilterDetailed": {"type": "any", "optional": true}}}], "optional": true}, "tableName": "string"}}}]}}, "dbsPermissions": {"info": {"hint": "Permission types and rules for the state database"}, "nullable": true, "jsonbSchemaType": {"createWorkspaces": {"type": "boolean", "optional": true}, "viewPublishedWorkspaces": {"type": {"workspaceIds": "string[]"}, "optional": true}}}, "llm_daily_limit": {"info": {"hint": "Maximum amount of queires per user/ip per 24hours"}, "sqlDefinition": "INTEGER NOT NULL DEFAULT 0 CHECK(llm_daily_limit >= 0)"}}}, "database_stats": {"columns": {"database_config_id": "INTEGER REFERENCES database_configs(id) ON DELETE SET NULL"}}, "login_attempts": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "sid": "TEXT", "info": "TEXT", "type": {"enum": ["web", "api_token", "mobile"], "nullable": false, "defaultValue": "web"}, "failed": "BOOLEAN", "created": "TIMESTAMP DEFAULT NOW()", "username": "TEXT", "auth_type": {"enum": ["session-id", "registration", "email-confirmation", "magic-link-registration", "magic-link", "otp-code", "login", "oauth"]}, "x_real_ip": "TEXT NOT NULL", "ip_address": "INET NOT NULL", "user_agent": "TEXT NOT NULL", "auth_provider": "TEXT CHECK(auth_type <> 'oauth' OR auth_provider IS NOT NULL)", "magic_link_id": "TEXT", "ip_address_remote": "TEXT NOT NULL"}}, "alert_viewed_by": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "viewed": "TIMESTAMP DEFAULT NOW()", "user_id": "UUID REFERENCES users(id) ON DELETE CASCADE", "alert_id": "BIGINT REFERENCES alerts(id) ON DELETE CASCADE"}}, "global_settings": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "updated_at": {"sqlDefinition": "TIMESTAMP NOT NULL DEFAULT now()"}, "updated_by": {"enum": ["user", "app"], "defaultValue": "app"}, "allowed_ips": {"info": {"hint": "List of allowed IP addresses in ipv4 or ipv6 format"}, "label": "Allowed IPs and subnets", "sqlDefinition": "cidr[] NOT NULL DEFAULT '{}'"}, "enable_logs": {"info": {"hint": "Logs are saved in the logs table from the state database"}, "label": "Enable logs (experimental)", "sqlDefinition": "boolean NOT NULL DEFAULT FALSE"}, "tableConfig": {"info": {"hint": "Schema used to create prostgles-ui"}, "sqlDefinition": "JSONB"}, "trust_proxy": {"info": {"hint": "If true then will use the IP from 'X-Forwarded-For' header"}, "sqlDefinition": "boolean NOT NULL DEFAULT FALSE"}, "allowed_origin": {"info": {"hint": "Specifies which domains can access this app in a cross-origin manner. \\nSets the Access-Control-Allow-Origin header. \\nUse '*' or a specific URL to allow API access"}, "label": "Allow-Origin", "sqlDefinition": "TEXT"}, "auth_providers": {"info": {"hint": "The provided credentials will allow users to register and sign in. The redirect uri format is {website_url}/auth/{providerName}/callback"}, "nullable": true, "jsonbSchemaType": {"email": {"optional": true, "oneOfType": [{"smtp": {"oneOfType": [{"host": {"type": "string"}, "pass": {"type": "string"}, "port": {"type": "number"}, "type": {"enum": ["smtp"]}, "user": {"type": "string"}, "secure": {"type": "boolean", "optional": true}, "rejectUnauthorized": {"type": "boolean", "optional": true}}, {"type": {"enum": ["aws-ses"]}, "region": {"type": "string"}, "accessKeyId": {"type": "string"}, "sendingRate": {"type": "integer", "optional": true}, "secretAccessKey": {"type": "string"}}]}, "enabled": {"type": "boolean", "optional": true}, "signupType": {"enum": ["withMagicLink"]}, "emailTemplate": {"type": {"body": "string", "from": "string", "subject": "string"}, "title": "Email template used for sending auth emails. Must contain placeholders for the url: ${url}"}, "emailConfirmationEnabled": {"type": "boolean", "title": "Enable email confirmation", "optional": true}}, {"smtp": {"oneOfType": [{"host": {"type": "string"}, "pass": {"type": "string"}, "port": {"type": "number"}, "type": {"enum": ["smtp"]}, "user": {"type": "string"}, "secure": {"type": "boolean", "optional": true}, "rejectUnauthorized": {"type": "boolean", "optional": true}}, {"type": {"enum": ["aws-ses"]}, "region": {"type": "string"}, "accessKeyId": {"type": "string"}, "sendingRate": {"type": "integer", "optional": true}, "secretAccessKey": {"type": "string"}}]}, "enabled": {"type": "boolean", "optional": true}, "signupType": {"enum": ["withPassword"]}, "emailTemplate": {"type": {"body": "string", "from": "string", "subject": "string"}, "title": "Email template used for sending auth emails. Must contain placeholders for the url: ${url}"}, "minPasswordLength": {"type": "integer", "title": "Minimum password length", "optional": true}, "emailConfirmationEnabled": {"type": "boolean", "title": "Enable email confirmation", "optional": true}}]}, "github": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["read:user", "user:email"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "google": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["profile", "email", "calendar", "calendar.readonly", "calendar.events", "calendar.events.readonly"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "facebook": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["email", "public_profile", "user_birthday", "user_friends", "user_gender", "user_hometown"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "microsoft": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["openid", "profile", "email", "offline_access", "User.Read", "User.ReadBasic.All", "User.Read.All"]}, "prompt": {"enum": ["login", "none", "consent", "select_account", "create"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "customOAuth": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]"}}, "optional": true}, "clientID": {"type": "string"}, "tokenURL": {"type": "string"}, "displayName": {"type": "string"}, "clientSecret": {"type": "string"}, "displayIconPath": {"type": "string", "optional": true}, "authorizationURL": {"type": "string"}}, "optional": true}, "website_url": {"type": "string", "title": "Website URL"}, "created_user_type": {"type": "string", "title": "User type assigned to new users. Defaults to 'default'", "optional": true}}}, "login_rate_limit": {"info": {"hint": "List of allowed IP addresses in ipv4 or ipv6 format"}, "label": "Failed login rate limit options", "defaultValue": {"groupBy": "ip", "maxAttemptsPerHour": 5}, "jsonbSchemaType": {"groupBy": {"enum": ["x-real-ip", "remote_ip", "ip"], "description": "The IP address used to group login attempts"}, "maxAttemptsPerHour": {"type": "integer", "description": "Maximum number of login attempts allowed per hour"}}}, "allowed_ips_enabled": {"info": {"hint": "If enabled then only allowed IPs can connect"}, "sqlDefinition": "BOOLEAN NOT NULL DEFAULT FALSE CHECK(allowed_ips_enabled = FALSE OR cardinality(allowed_ips) > 0)"}, "session_max_age_days": {"info": {"max": 9007199254740991, "min": 1, "hint": "Number of days a user will stay logged in"}, "sqlDefinition": "INTEGER NOT NULL DEFAULT 14 CHECK(session_max_age_days > 0)"}, "prostgles_registration": {"info": {"hint": "Registration options"}, "nullable": true, "jsonbSchemaType": {"email": {"type": "string"}, "token": {"type": "string"}, "enabled": {"type": "boolean"}}}, "login_rate_limit_enabled": {"info": {"hint": "If enabled then each client defined by <groupBy> that fails <maxAttemptsPerHour> in an hour will not be able to login for the rest of the hour"}, "label": "Enable failed login rate limit", "sqlDefinition": "BOOLEAN NOT NULL DEFAULT TRUE"}, "magic_link_validity_days": {"info": {"max": 9007199254740991, "min": 1, "hint": "Number of days a magic link can be used to log in"}, "sqlDefinition": "INTEGER NOT NULL DEFAULT 1 CHECK(magic_link_validity_days > 0)"}, "pass_process_env_vars_to_server_side_functions": {"info": {"hint": "If true then all environment variables will be passed to the server side function nodejs. Use at your own risk"}, "sqlDefinition": "BOOLEAN NOT NULL DEFAULT FALSE"}}, "triggers": {"Update updated_at": {"type": "before", "query": "\\n          BEGIN\\n            NEW.updated_at = now();\\n            RETURN NEW;\\n          END;\\n        ", "actions": ["update"], "forEach": "row"}}}, "llm_credentials": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "name": "TEXT NOT NULL DEFAULT 'Default credential'", "config": {"jsonbSchema": {"oneOfType": [{"model": {"type": "string"}, "API_Key": {"type": "string"}, "Provider": {"enum": ["OpenAI"]}, "temperature": {"type": "number", "optional": true}, "response_format": {"enum": ["json", "text", "srt", "verbose_json", "vtt"], "optional": true}, "presence_penalty": {"type": "number", "optional": true}, "frequency_penalty": {"type": "number", "optional": true}, "max_completion_tokens": {"type": "integer", "optional": true}}, {"model": {"type": "string"}, "API_Key": {"type": "string"}, "Provider": {"enum": ["Anthropic"]}, "max_tokens": {"type": "integer"}, "anthropic-version": {"type": "string"}}, {"body": {"record": {"values": "string"}, "optional": true}, "headers": {"record": {"values": "string"}, "optional": true}, "Provider": {"enum": ["Custom"]}}, {"API_Key": {"type": "string"}, "Provider": {"enum": ["Prostgles"]}}]}, "defaultValue": {"model": "gpt-4o", "API_Key": "", "Provider": "OpenAI"}}, "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "endpoint": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'https://api.openai.com/v1/chat/completions'"}, "is_default": {"info": {"hint": "If true then this is the default credential"}, "sqlDefinition": "BOOLEAN DEFAULT FALSE"}, "result_path": {"info": {"hint": "Will use corect defaults for OpenAI and Anthropic. Path to text response. E.g.: choices,0,message,content"}, "sqlDefinition": "_TEXT "}}, "indexes": {"unique_default": {"where": "is_default = TRUE", "unique": true, "columns": "is_default"}, "unique_llm_credential_name": {"unique": true, "columns": "name, user_id"}}}, "credential_types": {"isLookupTable": {"values": {"s3": {}}}}, "database_configs": {"columns": {"id": "SERIAL PRIMARY KEY", "db_host": "TEXT NOT NULL", "db_name": "TEXT NOT NULL", "db_port": "INTEGER NOT NULL", "sync_users": "BOOLEAN DEFAULT FALSE", "table_config": {"info": {"hint": "Table configurations"}, "nullable": true, "jsonbSchema": {"record": {"values": {"oneOfType": [{"isLookupTable": {"type": {"values": {"record": {"values": {"type": "string", "optional": true}}}}}}, {"columns": {"record": {"values": {"oneOf": ["string", {"type": {"hint": {"type": "string", "optional": true}, "isText": {"type": "boolean", "optional": true}, "trimmed": {"type": "boolean", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "defaultValue": {"type": "any", "optional": true}}}, {"type": {"jsonbSchema": {"oneOfType": [{"type": {"enum": ["string", "number", "boolean", "Date", "time", "timestamp", "string[]", "number[]", "boolean[]", "Date[]", "time[]", "timestamp[]"]}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}}, {"type": {"enum": ["Lookup", "Lookup[]"]}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}}, {"type": {"enum": ["object"]}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}}]}}}]}}, "description": "Column definitions and hints"}}]}}}}, "backups_config": {"info": {"hint": "Automatic backups configurations"}, "nullable": true, "jsonbSchemaType": {"err": {"type": "string", "nullable": true, "optional": true}, "hour": {"type": "integer", "optional": true}, "enabled": {"type": "boolean", "optional": true}, "keepLast": {"type": "integer", "optional": true}, "dayOfWeek": {"type": "integer", "optional": true}, "frequency": {"enum": ["daily", "monthly", "weekly", "hourly"]}, "dayOfMonth": {"type": "integer", "optional": true}, "cloudConfig": {"type": {"credential_id": {"type": "number", "nullable": true, "optional": true}}, "nullable": true}, "dump_options": {"oneOfType": [{"clean": {"type": "boolean"}, "command": {"enum": ["pg_dumpall"]}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "rolesOnly": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "globalsOnly": {"type": "boolean", "optional": true}}, {"clean": {"type": "boolean", "optional": true}, "create": {"type": "boolean", "optional": true}, "format": {"enum": ["p", "t", "c"]}, "command": {"enum": ["pg_dump"]}, "noOwner": {"type": "boolean", "optional": true}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "numberOfJobs": {"type": "integer", "optional": true}, "excludeSchema": {"type": "string", "optional": true}, "compressionLevel": {"type": "integer", "optional": true}}]}}}, "table_config_ts": {"info": {"hint": "Table configurations from typescript. Must export const tableConfig"}, "sqlDefinition": "TEXT"}, "rest_api_enabled": "BOOLEAN DEFAULT FALSE", "file_table_config": {"info": {"hint": "File storage configurations"}, "nullable": true, "jsonbSchemaType": {"fileTable": {"type": "string", "optional": true}, "storageType": {"oneOfType": [{"type": {"enum": ["local"]}}, {"type": {"enum": ["S3"]}, "credential_id": {"type": "number"}}]}, "delayedDelete": {"type": {"deleteAfterNDays": {"type": "number"}, "checkIntervalHours": {"type": "number", "optional": true}}, "optional": true}, "referencedTables": {"type": "any", "optional": true}}}, "table_config_ts_disabled": {"info": {"hint": "If true then Table configurations will not be executed"}, "sqlDefinition": "BOOLEAN"}}, "constraints": {"uniqueDatabase": {"type": "UNIQUE", "content": "db_name, db_host, db_port"}}}, "published_methods": {"columns": {"id": "SERIAL PRIMARY KEY", "run": "TEXT NOT NULL DEFAULT 'export const run: ProstglesMethod = async (args, { db, dbo, user }) => {\\n  \\n}'", "name": "TEXT NOT NULL DEFAULT 'Method name'", "arguments": {"nullable": false, "jsonbSchema": {"title": "Arguments", "arrayOf": {"oneOfType": [{"name": {"type": "string", "title": "Argument name"}, "type": {"enum": ["any", "string", "number", "boolean", "Date", "time", "timestamp", "string[]", "number[]", "boolean[]", "Date[]", "time[]", "timestamp[]"], "title": "Data type"}, "optional": {"type": "boolean", "title": "Optional", "optional": true}, "defaultValue": {"type": "string", "optional": true}, "allowedValues": {"type": "string[]", "title": "Allowed values", "optional": true}}, {"name": {"type": "string", "title": "Argument name"}, "type": {"enum": ["Lookup", "Lookup[]"], "title": "Data type"}, "lookup": {"title": "Table column", "lookup": {"type": "data-def", "table": "", "column": ""}}, "optional": {"type": "boolean", "optional": true}, "defaultValue": {"type": "any", "optional": true}}, {"name": {"type": "string", "title": "Argument name"}, "type": {"enum": ["JsonbSchema"], "title": "Data type"}, "schema": {"title": "Jsonb schema", "oneOfType": [{"type": {"enum": ["boolean", "number", "integer", "string", "Date", "time", "timestamp", "any", "boolean[]", "number[]", "integer[]", "string[]", "Date[]", "time[]", "timestamp[]", "any[]"]}, "title": {"type": "string", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}, "defaultValue": {"type": "any", "optional": true}}, {"type": {"enum": ["object", "object[]"]}, "title": {"type": "string", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "optional": {"type": "boolean", "optional": true}, "properties": {"record": {"values": {"type": {"type": {"enum": ["boolean", "number", "integer", "string", "Date", "time", "timestamp", "any", "boolean[]", "number[]", "integer[]", "string[]", "Date[]", "time[]", "timestamp[]", "any[]"]}, "title": {"type": "string", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}, "defaultValue": {"type": "any", "optional": true}}}}}, "description": {"type": "string", "optional": true}, "defaultValue": {"type": "any", "optional": true}}]}, "optional": {"type": "boolean", "optional": true}, "defaultValue": {"type": "any", "optional": true}}]}}, "defaultValue": "[]"}, "description": "TEXT NOT NULL DEFAULT 'Method description'", "outputTable": "TEXT", "connection_id": {"info": {"hint": "If null then connection was deleted"}, "sqlDefinition": "UUID REFERENCES connections(id) ON DELETE SET NULL"}}, "indexes": {"unique_name": {"unique": true, "columns": "connection_id, name"}}}, "database_config_logs": {"columns": {"id": "SERIAL PRIMARY KEY REFERENCES database_configs (id) ON DELETE CASCADE", "on_run_logs": {"info": {"hint": "On mount logs"}, "sqlDefinition": "TEXT"}, "on_mount_logs": {"info": {"hint": "On mount logs"}, "sqlDefinition": "TEXT"}, "table_config_logs": {"info": {"hint": "On mount logs"}, "sqlDefinition": "TEXT"}}}, "access_control_methods": {"columns": {"access_control_id": "INTEGER NOT NULL REFERENCES access_control  ON DELETE CASCADE", "published_method_id": "INTEGER NOT NULL REFERENCES published_methods  ON DELETE CASCADE"}, "constraints": {"pkey": {"type": "PRIMARY KEY", "content": "published_method_id, access_control_id"}}}, "workspace_publish_modes": {"isLookupTable": {"values": {"fixed": {"en": "Fixed", "description": "The workspace layout is fixed"}, "editable": {"en": "Editable", "description": "The workspace will be cloned layout for each user"}}}}, "access_control_user_types": {"columns": {"user_type": "TEXT NOT NULL REFERENCES user_types(id)  ON DELETE CASCADE", "access_control_id": "INTEGER NOT NULL REFERENCES access_control(id)  ON DELETE CASCADE"}, "constraints": {"NoDupes": "UNIQUE(access_control_id, user_type)"}}, "access_control_allowed_llm": {"columns": {"llm_prompt_id": "INTEGER NOT NULL REFERENCES llm_prompts(id)", "access_control_id": "INTEGER NOT NULL REFERENCES access_control(id)", "llm_credential_id": "INTEGER NOT NULL REFERENCES llm_credentials(id)"}, "indexes": {"unique": {"unique": true, "columns": "access_control_id, llm_credential_id, llm_prompt_id"}}}, "access_control_connections": {"columns": {"connection_id": "UUID NOT NULL REFERENCES connections(id) ON DELETE CASCADE", "access_control_id": "INTEGER NOT NULL REFERENCES access_control  ON DELETE CASCADE"}, "indexes": {"unique_connection_id": {"unique": true, "columns": "connection_id, access_control_id"}}}}	\N
\.


--
-- Data for Name: historico_capturas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.historico_capturas (id, codigo_barras, item_code, resultado, motivo, cumple, usuario, fecha_captura, procesado) FROM stdin;
\.


--
-- Data for Name: items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.items (id, item, resultado, fecha_actualizacion) FROM stdin;
1	4925430	NO CUMPLE	2025-07-07 19:21:00
2	4871309	NO CUMPLE	2025-07-07 19:21:00
3	5094826	NO CUMPLE	2025-07-07 19:21:00
4	4312665	NO CUMPLE	2025-07-07 19:21:00
5	4518513	NO CUMPLE	2025-07-07 19:21:00
6	4178894	CUMPLE	2025-07-07 19:21:00
7	4833468	NO CUMPLE	2025-07-07 19:21:00
8	2941351	NO CUMPLE	2025-07-07 19:21:00
9	4047131	CUMPLE	2025-07-07 19:21:00
10	5446586	CUMPLE	2025-07-07 19:21:00
11	2562325	NO CUMPLE	2025-07-07 19:21:00
12	5407486	NO CUMPLE	2025-07-07 19:21:00
13	4925465	NO CUMPLE	2025-07-07 19:21:00
14	5216787	CUMPLE	2025-07-07 19:21:00
15	2385647	NO CUMPLE	2025-07-07 19:21:00
16	4361592	NO CUMPLE	2025-07-07 19:21:00
17	4927568	NO CUMPLE	2025-07-07 19:21:00
18	5514125	CUMPLE	2025-07-07 19:21:00
19	4284181	CUMPLE	2025-07-07 19:21:00
20	5516002	CUMPLE	2025-07-07 19:21:00
21	5334007	CUMPLE	2025-07-07 19:21:00
22	4359091	CUMPLE	2025-07-07 19:21:00
23	4925427	NO CUMPLE	2025-07-07 19:21:00
24	5304382	CUMPLE	2025-07-07 19:21:00
25	5145646	CUMPLE	2025-07-07 19:21:00
26	5094984	CUMPLE	2025-07-07 19:21:00
27	5446581	CUMPLE	2025-07-07 19:21:00
28	5419848	CUMPLE	2025-07-07 19:21:00
29	4974995	CUMPLE	2025-07-07 19:21:00
30	4984796	CUMPLE	2025-07-07 19:21:00
31	4819784	NO CUMPLE	2025-07-07 19:21:00
32	5094825	NO CUMPLE	2025-07-07 19:21:00
33	4905563	CUMPLE	2025-07-07 19:21:00
34	4494178	NO CUMPLE	2025-07-07 19:21:00
35	4755781	NO CUMPLE	2025-07-07 19:21:00
36	2432300	NO CUMPLE	2025-07-07 19:21:00
37	4094319	NO CUMPLE	2025-07-07 19:21:00
38	2778462	NO CUMPLE	2025-07-07 19:21:00
39	2141870	NO CUMPLE	2025-07-07 19:21:00
40	5144175	NO CUMPLE	2025-07-07 19:21:00
41	5516206	CUMPLE	2025-07-07 19:21:00
42	5365797	CUMPLE	2025-07-07 19:21:00
43	4004083	CUMPLE	2025-07-07 19:21:00
44	4361205	NO CUMPLE	2025-07-07 19:21:00
45	5383756	CUMPLE	2025-07-07 19:21:00
46	4404588	NO CUMPLE	2025-07-07 19:21:00
47	4804185	NO CUMPLE	2025-07-07 19:21:00
48	5415090	CUMPLE	2025-07-07 19:21:00
49	4925458	CUMPLE	2025-07-07 19:21:00
50	4925457	CUMPLE	2025-07-07 19:21:00
51	4377758	NO CUMPLE	2025-07-07 19:21:00
52	5364101	CUMPLE	2025-07-07 19:21:00
53	5154030	CUMPLE	2025-07-07 19:21:00
54	4672307	CUMPLE	2025-07-07 19:21:00
55	4579638	CUMPLE	2025-07-07 19:21:00
56	5334006	CUMPLE	2025-07-07 19:21:00
57	5264056	CUMPLE	2025-07-07 19:21:00
58	5015078	NO CUMPLE	2025-07-07 19:21:00
59	2879948	NO CUMPLE	2025-07-07 19:21:00
60	4250454	CUMPLE	2025-07-07 19:21:00
61	4976497	CUMPLE	2025-07-07 19:21:00
62	5165159	CUMPLE	2025-07-07 19:21:00
63	2730750	CUMPLE	2025-07-07 19:21:00
64	4784076	NO CUMPLE	2025-07-07 19:21:00
65	4646550	NO CUMPLE	2025-07-07 19:21:00
66	4404592	NO CUMPLE	2025-07-07 19:21:00
67	5104597	NO CUMPLE	2025-07-07 19:21:00
68	2561167	NO CUMPLE	2025-07-07 19:21:00
69	2769548	NO CUMPLE	2025-07-07 19:21:00
70	4729906	NO CUMPLE	2025-07-07 19:21:00
71	2121844	NO CUMPLE	2025-07-07 19:21:00
72	4808759	NO CUMPLE	2025-07-07 19:21:00
73	4698030	NO CUMPLE	2025-07-07 19:21:00
74	4773410	CUMPLE	2025-07-07 19:21:00
75	5205546	CUMPLE	2025-07-07 19:21:00
76	4925445	NO CUMPLE	2025-07-07 19:21:00
77	2956722	NO CUMPLE	2025-07-07 19:21:00
78	4359090	CUMPLE	2025-07-07 19:21:00
79	2707972	NO CUMPLE	2025-07-07 19:21:00
80	5055652	NO CUMPLE	2025-07-07 19:21:00
81	4127871	NO CUMPLE	2025-07-07 19:21:00
82	2658141	NO CUMPLE	2025-07-07 19:21:00
83	2115509	CUMPLE	2025-07-07 19:21:00
84	5254087	CUMPLE	2025-07-07 19:21:00
85	5447088	NO CUMPLE	2025-07-07 19:21:00
86	2718960	NO CUMPLE	2025-07-07 19:21:00
87	4781338	NO CUMPLE	2025-07-07 19:21:00
88	4848148	CUMPLE	2025-07-07 19:21:00
89	2944993	NO CUMPLE	2025-07-07 19:21:00
90	4304118	NO CUMPLE	2025-07-07 19:21:00
91	4315751	NO CUMPLE	2025-07-07 19:21:00
92	2688019	NO CUMPLE	2025-07-07 19:21:00
93	4925429	NO CUMPLE	2025-07-07 19:21:00
94	5064147	CUMPLE	2025-07-07 19:21:00
95	4954492	NO CUMPLE	2025-07-07 19:21:00
96	4177967	NO CUMPLE	2025-07-07 19:21:00
97	2604692	NO CUMPLE	2025-07-07 19:21:00
98	4425647	NO CUMPLE	2025-07-07 19:21:00
99	4567160	NO CUMPLE	2025-07-07 19:21:00
100	4329993	NO CUMPLE	2025-07-07 19:21:00
101	5205547	CUMPLE	2025-07-07 19:21:00
102	2697567	CUMPLE	2025-07-07 19:21:00
103	2900270	NO CUMPLE	2025-07-07 19:21:00
104	2408514	NO CUMPLE	2025-07-07 19:21:00
105	2611002	CUMPLE	2025-07-07 19:21:00
106	5415538	CUMPLE	2025-07-07 19:21:00
107	4531445	CUMPLE	2025-07-07 19:21:00
108	2885154	CUMPLE	2025-07-07 19:21:00
109	4313280	NO CUMPLE	2025-07-07 19:21:00
110	4326471	NO CUMPLE	2025-07-07 19:21:00
111	4193276	NO CUMPLE	2025-07-07 19:21:00
112	5447074	NO CUMPLE	2025-07-07 19:21:00
113	2356818	NO CUMPLE	2025-07-07 19:21:00
114	5055653	NO CUMPLE	2025-07-07 19:21:00
115	2170742	NO CUMPLE	2025-07-07 19:21:00
116	4374780	NO CUMPLE	2025-07-07 19:21:00
117	4874184	NO CUMPLE	2025-07-07 19:21:00
118	4579088	NO CUMPLE	2025-07-07 19:21:00
119	2616342	NO CUMPLE	2025-07-07 19:21:00
120	4320939	NO CUMPLE	2025-07-07 19:21:00
121	4010710	NO CUMPLE	2025-07-07 19:21:00
122	2531588	NO CUMPLE	2025-07-07 19:21:00
123	2531586	NO CUMPLE	2025-07-07 19:21:00
124	2532762	CUMPLE	2025-07-07 19:21:00
125	5345036	CUMPLE	2025-07-07 19:21:00
126	4173233	CUMPLE	2025-07-07 19:21:00
127	4327542	CUMPLE	2025-07-07 19:21:00
128	4954494	NO CUMPLE	2025-07-07 19:21:00
129	4954493	NO CUMPLE	2025-07-07 19:21:00
130	4954497	NO CUMPLE	2025-07-07 19:21:00
131	4954495	NO CUMPLE	2025-07-07 19:21:00
132	4954496	NO CUMPLE	2025-07-07 19:21:00
133	2780008	NO CUMPLE	2025-07-07 19:21:00
134	4925455	CUMPLE	2025-07-07 19:21:00
135	4925454	CUMPLE	2025-07-07 19:21:00
136	4925456	CUMPLE	2025-07-07 19:21:00
137	5417451	CUMPLE	2025-07-07 19:21:00
138	5509282	CUMPLE	2025-07-07 19:21:00
139	5028197	NO CUMPLE	2025-07-07 19:21:00
140	5101411	NO CUMPLE	2025-07-07 19:21:00
141	4427551	NO CUMPLE	2025-07-07 19:21:00
142	4843878	NO CUMPLE	2025-07-07 19:21:00
143	4772642	NO CUMPLE	2025-07-07 19:21:00
144	2835081	NO CUMPLE	2025-07-07 19:21:00
145	4351389	NO CUMPLE	2025-07-07 19:21:00
146	4717930	NO CUMPLE	2025-07-07 19:21:00
147	5177536	NO CUMPLE	2025-07-07 19:21:00
148	2754031	CUMPLE	2025-07-07 19:21:00
149	4252494	NO CUMPLE	2025-07-07 19:21:00
150	5306335	CUMPLE	2025-07-07 19:21:00
151	5394295	CUMPLE	2025-07-07 19:21:00
152	2962694	NO CUMPLE	2025-07-07 19:21:00
153	5330560	CUMPLE	2025-07-07 19:21:00
154	4403327	NO CUMPLE	2025-07-07 19:21:00
155	5330544	CUMPLE	2025-07-07 19:21:00
156	4898580	CUMPLE	2025-07-07 19:21:00
157	5394298	CUMPLE	2025-07-07 19:21:00
158	2141869	CUMPLE	2025-07-07 19:21:00
159	2141868	CUMPLE	2025-07-07 19:21:00
160	2141867	CUMPLE	2025-07-07 19:21:00
161	2141865	CUMPLE	2025-07-07 19:21:00
162	4925484	CUMPLE	2025-07-07 19:21:00
163	4925483	CUMPLE	2025-07-07 19:21:00
164	4925482	CUMPLE	2025-07-07 19:21:00
165	2191617	NO CUMPLE	2025-07-07 19:21:00
166	2191616	NO CUMPLE	2025-07-07 19:21:00
167	2191615	NO CUMPLE	2025-07-07 19:21:00
168	2191614	NO CUMPLE	2025-07-07 19:21:00
169	4808744	NO CUMPLE	2025-07-07 19:21:00
170	2176335	CUMPLE	2025-07-07 19:21:00
171	2176334	CUMPLE	2025-07-07 19:21:00
172	2176333	CUMPLE	2025-07-07 19:21:00
173	2176332	CUMPLE	2025-07-07 19:21:00
174	2176331	CUMPLE	2025-07-07 19:21:00
175	2176330	CUMPLE	2025-07-07 19:21:00
176	2176329	CUMPLE	2025-07-07 19:21:00
177	5117916	NO CUMPLE	2025-07-07 19:21:00
178	5117914	NO CUMPLE	2025-07-07 19:21:00
179	5117913	NO CUMPLE	2025-07-07 19:21:00
180	5117912	NO CUMPLE	2025-07-07 19:21:00
181	5117911	NO CUMPLE	2025-07-07 19:21:00
182	410868	NO CUMPLE	2025-07-07 19:21:00
183	4899301	NO CUMPLE	2025-07-07 19:21:00
184	5245479	NO CUMPLE	2025-07-07 19:21:00
185	5245478	NO CUMPLE	2025-07-07 19:21:00
186	5245477	NO CUMPLE	2025-07-07 19:21:00
187	5245474	NO CUMPLE	2025-07-07 19:21:00
188	5245473	NO CUMPLE	2025-07-07 19:21:00
189	5245472	NO CUMPLE	2025-07-07 19:21:00
190	2745729	NO CUMPLE	2025-07-07 19:21:00
191	5325319	CUMPLE	2025-07-07 19:21:00
192	5274647	CUMPLE	2025-07-07 19:21:00
193	4340731	NO CUMPLE	2025-07-07 19:21:00
194	2940962	NO CUMPLE	2025-07-07 19:21:00
195	4997216	CUMPLE	2025-07-07 19:21:00
196	4857572	CUMPLE	2025-07-07 19:21:00
197	4823513	NO CUMPLE	2025-07-07 19:21:00
198	4356016	NO CUMPLE	2025-07-07 19:21:00
199	4287521	NO CUMPLE	2025-07-07 19:21:00
200	5415537	CUMPLE	2025-07-07 19:21:00
201	5551790	CUMPLE	2025-07-07 19:21:00
202	4467300	NO CUMPLE	2025-07-07 19:21:00
203	4523554	NO CUMPLE	2025-07-07 19:21:00
204	5178055	NO CUMPLE	2025-07-07 19:21:00
205	4049129	CUMPLE	2025-07-07 19:21:00
206	4311238	NO CUMPLE	2025-07-07 19:21:00
207	2838005	NO CUMPLE	2025-07-07 19:21:00
208	X	NO CUMPLE	2025-07-07 19:21:00
209	4350186	NO CUMPLE	2025-07-07 19:21:00
210	4273718	NO CUMPLE	2025-07-07 19:21:00
211	4185048	CUMPLE	2025-07-07 19:21:00
212	5304381	CUMPLE	2025-07-07 19:21:00
213	5414198	CUMPLE	2025-07-07 19:21:00
214	5445458	NO CUMPLE	2025-07-07 19:21:00
215	5445459	NO CUMPLE	2025-07-07 19:21:00
216	4156855	NO CUMPLE	2025-07-07 19:21:00
217	2563929	NO CUMPLE	2025-07-07 19:21:00
218	540892	CUMPLE	2025-07-07 19:21:00
219	2235828	CUMPLE	2025-07-07 19:21:00
220	2016115	NO CUMPLE	2025-07-07 19:21:00
221	2712386	NO CUMPLE	2025-07-07 19:21:00
222	2422755	NO CUMPLE	2025-07-07 19:21:00
223	2899415	NO CUMPLE	2025-07-07 19:21:00
224	2044651	NO CUMPLE	2025-07-07 19:21:00
225	4271999	CUMPLE	2025-07-07 19:21:00
226	5446585	CUMPLE	2025-07-07 19:21:00
227	4820923	CUMPLE	2025-07-07 19:21:00
228	4784075	NO CUMPLE	2025-07-07 19:21:00
229	2908940	NO CUMPLE	2025-07-07 19:21:00
230	1650966	NO CUMPLE	2025-07-07 19:21:00
231	4227717	CUMPLE	2025-07-07 19:21:00
232	4794269	CUMPLE	2025-07-07 19:21:00
233	4531444	NO CUMPLE	2025-07-07 19:21:00
234	2509644	CUMPLE	2025-07-07 19:21:00
235	5223933	NO CUMPLE	2025-07-07 19:21:00
236	5324344	CUMPLE	2025-07-07 19:21:00
237	4984795	CUMPLE	2025-07-07 19:21:00
238	4984798	CUMPLE	2025-07-07 19:21:00
239	4313947	NO CUMPLE	2025-07-07 19:21:00
240	4315750	NO CUMPLE	2025-07-07 19:21:00
241	2726081	CUMPLE	2025-07-07 19:21:00
242	4933896	NO CUMPLE	2025-07-07 19:21:00
243	699393	NO CUMPLE	2025-07-07 19:21:00
244	2181821	CUMPLE	2025-07-07 19:21:00
245	5504110	CUMPLE	2025-07-07 19:21:00
246	5399150	CUMPLE	2025-07-07 19:21:00
247	4484568	CUMPLE	2025-07-07 19:21:00
248	2775164	NO CUMPLE	2025-07-07 19:21:00
249	2648459	NO CUMPLE	2025-07-07 19:21:00
250	5485697	CUMPLE	2025-07-07 19:21:00
251	1272191	NO CUMPLE	2025-07-07 19:21:00
252	4810158	NO CUMPLE	2025-07-07 19:21:00
253	4964786	CUMPLE	2025-07-07 19:21:00
254	5514492	CUMPLE	2025-07-07 19:21:00
255	2953481	CUMPLE	2025-07-07 19:21:00
256	2730434	CUMPLE	2025-07-07 19:21:00
257	4531543	CUMPLE	2025-07-07 19:21:00
258	4531544	CUMPLE	2025-07-07 19:21:00
259	4630474	NO CUMPLE	2025-07-07 19:21:00
260	2941176	CUMPLE	2025-07-07 19:21:00
261	4767834	CUMPLE	2025-07-07 19:21:00
262	5417709	CUMPLE	2025-07-07 19:21:00
263	4385480	CUMPLE	2025-07-07 19:21:00
264	4838919	NO CUMPLE	2025-07-07 19:21:00
265	4819795	NO CUMPLE	2025-07-07 19:21:00
266	4925448	NO CUMPLE	2025-07-07 19:21:00
267	4881889	NO CUMPLE	2025-07-07 19:21:00
268	4761798	NO CUMPLE	2025-07-07 19:21:00
269	4761508	NO CUMPLE	2025-07-07 19:21:00
270	4566182	NO CUMPLE	2025-07-07 19:21:00
271	4997188	NO CUMPLE	2025-07-07 19:21:00
272	1347579	NO CUMPLE	2025-07-07 19:21:00
273	4925413	CUMPLE	2025-07-07 19:21:00
274	4364837	NO CUMPLE	2025-07-07 19:21:00
275	4103708	NO CUMPLE	2025-07-07 19:21:00
276	4326640	CUMPLE	2025-07-07 19:21:00
277	4233067	NO CUMPLE	2025-07-07 19:21:00
278	4166949	NO CUMPLE	2025-07-07 19:21:00
279	4325325	NO CUMPLE	2025-07-07 19:21:00
280	4545843	NO CUMPLE	2025-07-07 19:21:00
281	5055366	NO CUMPLE	2025-07-07 19:21:00
282	4301986	NO CUMPLE	2025-07-07 19:21:00
283	2691830	NO CUMPLE	2025-07-07 19:21:00
284	4434837	NO CUMPLE	2025-07-07 19:21:00
285	54192771	NO CUMPLE	2025-07-07 19:21:00
286	2910279	NO CUMPLE	2025-07-07 19:21:00
287	2884484	NO CUMPLE	2025-07-07 19:21:00
288	5064354	NO CUMPLE	2025-07-07 19:21:00
289	4192771	NO CUMPLE	2025-07-07 19:21:00
290	4243497	NO CUMPLE	2025-07-07 19:21:00
291	1681552	NO CUMPLE	2025-07-07 19:21:00
292	4747827	CUMPLE	2025-07-07 19:21:00
293	5379563	CUMPLE	2025-07-07 19:21:00
294	4647180	NO CUMPLE	2025-07-07 19:21:00
295	4867868	NO CUMPLE	2025-07-07 19:21:00
296	4194022	CUMPLE	2025-07-07 19:21:00
297	5184313	CUMPLE	2025-07-07 19:21:00
298	4713660	CUMPLE	2025-07-07 19:21:00
299	2745750	NO CUMPLE	2025-07-07 19:21:00
300	5415173	CUMPLE	2025-07-07 19:21:00
301	4367775	CUMPLE	2025-07-07 19:21:00
302	5225077	NO CUMPLE	2025-07-07 19:21:00
303	4757499	NO CUMPLE	2025-07-07 19:21:00
304	4996999	CUMPLE	2025-07-07 19:21:00
305	4546549	NO CUMPLE	2025-07-07 19:21:00
306	4393925	NO CUMPLE	2025-07-07 19:21:00
307	4395631	NO CUMPLE	2025-07-07 19:21:00
308	2886232	NO CUMPLE	2025-07-07 19:21:00
309	4490290	NO CUMPLE	2025-07-07 19:21:00
310	2696441	NO CUMPLE	2025-07-07 19:21:00
311	4923860	NO CUMPLE	2025-07-07 19:21:00
312	4341738	NO CUMPLE	2025-07-07 19:21:00
313	4987295	NO CUMPLE	2025-07-07 19:21:00
314	4126912	NO CUMPLE	2025-07-07 19:21:00
315	2600305	NO CUMPLE	2025-07-07 19:21:00
316	4030683	NO CUMPLE	2025-07-07 19:21:00
317	4425704	NO CUMPLE	2025-07-07 19:21:00
318	4839793	NO CUMPLE	2025-07-07 19:21:00
319	4324844	NO CUMPLE	2025-07-07 19:21:00
320	4728754	CUMPLE	2025-07-07 19:21:00
321	2720566	NO CUMPLE	2025-07-07 19:21:00
322	4033282	NO CUMPLE	2025-07-07 19:21:00
323	2934793	NO CUMPLE	2025-07-07 19:21:00
324	4045308	NO CUMPLE	2025-07-07 19:21:00
325	4361603	NO CUMPLE	2025-07-07 19:21:00
326	2934540	CUMPLE	2025-07-07 19:21:00
327	5448226	NO CUMPLE	2025-07-07 19:21:00
328	5099785	CUMPLE	2025-07-07 19:21:00
329	5417434	CUMPLE	2025-07-07 19:21:00
330	4471974	NO CUMPLE	2025-07-07 19:21:00
331	5056498	NO CUMPLE	2025-07-07 19:21:00
332	5075458	NO CUMPLE	2025-07-07 19:21:00
333	4533407	NO CUMPLE	2025-07-07 19:21:00
334	5516933	CUMPLE	2025-07-07 19:21:00
335	4548163	NO CUMPLE	2025-07-07 19:21:00
336	5165754	NO CUMPLE	2025-07-07 19:21:00
337	4690994	CUMPLE	2025-07-07 19:21:00
338	5417461	CUMPLE	2025-07-07 19:21:00
339	712813	CUMPLE	2025-07-07 19:21:00
340	4361142	CUMPLE	2025-07-07 19:21:00
341	712811	CUMPLE	2025-07-07 19:21:00
342	712790	CUMPLE	2025-07-07 19:21:00
343	712792	CUMPLE	2025-07-07 19:21:00
344	411314	CUMPLE	2025-07-07 19:21:00
345	2308146	NO CUMPLE	2025-07-07 19:21:00
346	2172064	NO CUMPLE	2025-07-07 19:21:00
347	2722539	NO CUMPLE	2025-07-07 19:21:00
348	2722536	NO CUMPLE	2025-07-07 19:21:00
349	4596871	NO CUMPLE	2025-07-07 19:21:00
350	4682888	NO CUMPLE	2025-07-07 19:21:00
351	4682887	NO CUMPLE	2025-07-07 19:21:00
352	4682886	NO CUMPLE	2025-07-07 19:21:00
353	4682885	NO CUMPLE	2025-07-07 19:21:00
354	2900590	NO CUMPLE	2025-07-07 19:21:00
355	4478932	CUMPLE	2025-07-07 19:21:00
356	4976532	CUMPLE	2025-07-07 19:21:00
357	5024222	CUMPLE	2025-07-07 19:21:00
358	5193994	NO CUMPLE	2025-07-07 19:21:00
359	5256080	CUMPLE	2025-07-07 19:21:00
360	4010636	NO CUMPLE	2025-07-07 19:21:00
361	2386966	NO CUMPLE	2025-07-07 19:21:00
362	2189141	CUMPLE	2025-07-07 19:21:00
363	2189143	CUMPLE	2025-07-07 19:21:00
364	4572596	NO CUMPLE	2025-07-07 19:21:00
365	4843387	CUMPLE	2025-07-07 19:21:00
366	5419788	CUMPLE	2025-07-07 19:21:00
367	2459666	NO CUMPLE	2025-07-07 19:21:00
368	2899632	CUMPLE	2025-07-07 19:21:00
369	4335737	NO CUMPLE	2025-07-07 19:21:00
370	4405715	CUMPLE	2025-07-07 19:21:00
371	4449130	CUMPLE	2025-07-07 19:21:00
372	4964749	CUMPLE	2025-07-07 19:21:00
373	4290644	NO CUMPLE	2025-07-07 19:21:00
374	2707962	NO CUMPLE	2025-07-07 19:21:00
375	5350673	CUMPLE	2025-07-07 19:21:00
376	4023123	NO CUMPLE	2025-07-07 19:21:00
377	4480790	CUMPLE	2025-07-07 19:21:00
378	4480791	CUMPLE	2025-07-07 19:21:00
379	4037352	CUMPLE	2025-07-07 19:21:00
380	4364838	NO CUMPLE	2025-07-07 19:21:00
381	4713668	NO CUMPLE	2025-07-07 19:21:00
382	4271635	NO CUMPLE	2025-07-07 19:21:00
383	4325326	NO CUMPLE	2025-07-07 19:21:00
384	4565930	NO CUMPLE	2025-07-07 19:21:00
385	5055894	NO CUMPLE	2025-07-07 19:21:00
386	4545500	CUMPLE	2025-07-07 19:21:00
387	4349759	NO CUMPLE	2025-07-07 19:21:00
388	4349760	NO CUMPLE	2025-07-07 19:21:00
389	4349761	NO CUMPLE	2025-07-07 19:21:00
390	2921594	NO CUMPLE	2025-07-07 19:21:00
391	4924810	NO CUMPLE	2025-07-07 19:21:00
392	4924812	NO CUMPLE	2025-07-07 19:21:00
393	5264076	CUMPLE	2025-07-07 19:21:00
394	5411294	CUMPLE	2025-07-07 19:21:00
395	5411297	CUMPLE	2025-07-07 19:21:00
396	4695913	NO CUMPLE	2025-07-07 19:21:00
397	4792759	NO CUMPLE	2025-07-07 19:21:00
398	4103705	NO CUMPLE	2025-07-07 19:21:00
399	4232875	NO CUMPLE	2025-07-07 19:21:00
400	4308506	NO CUMPLE	2025-07-07 19:21:00
401	4819785	NO CUMPLE	2025-07-07 19:21:00
402	4819793	NO CUMPLE	2025-07-07 19:21:00
403	5014860	NO CUMPLE	2025-07-07 19:21:00
404	5014861	NO CUMPLE	2025-07-07 19:21:00
405	1862900	NO CUMPLE	2025-07-07 19:21:00
406	1862902	NO CUMPLE	2025-07-07 19:21:00
407	4486492	NO CUMPLE	2025-07-07 19:21:00
408	4899393	NO CUMPLE	2025-07-07 19:21:00
409	4438964	NO CUMPLE	2025-07-07 19:21:00
410	4816922	NO CUMPLE	2025-07-07 19:21:00
411	4777194	NO CUMPLE	2025-07-07 19:21:00
412	2475299	NO CUMPLE	2025-07-07 19:21:00
413	2959084	NO CUMPLE	2025-07-07 19:21:00
414	2652352	NO CUMPLE	2025-07-07 19:21:00
415	2885150	CUMPLE	2025-07-07 19:21:00
416	2943847	NO CUMPLE	2025-07-07 19:21:00
417	5193932	CUMPLE	2025-07-07 19:21:00
418	2577132	NO CUMPLE	2025-07-07 19:21:00
419	2755540	NO CUMPLE	2025-07-07 19:21:00
420	4548165	NO CUMPLE	2025-07-07 19:21:00
421	4844147	NO CUMPLE	2025-07-07 19:21:00
422	5064902	NO CUMPLE	2025-07-07 19:21:00
423	4019530	NO CUMPLE	2025-07-07 19:21:00
424	4016596	NO CUMPLE	2025-07-07 19:21:00
425	4016597	NO CUMPLE	2025-07-07 19:21:00
426	4016598	NO CUMPLE	2025-07-07 19:21:00
427	2715579	NO CUMPLE	2025-07-07 19:21:00
428	2912142	NO CUMPLE	2025-07-07 19:21:00
429	4735700	NO CUMPLE	2025-07-07 19:21:00
430	4561948	NO CUMPLE	2025-07-07 19:21:00
431	4071611	NO CUMPLE	2025-07-07 19:21:00
432	5000001	NO CUMPLE	2025-07-07 19:21:00
433	5000002	NO CUMPLE	2025-07-07 19:21:00
434	2771868	NO CUMPLE	2025-07-07 19:21:00
435	2908942	NO CUMPLE	2025-07-07 19:21:00
436	2836836	NO CUMPLE	2025-07-07 19:21:00
437	5177609	CUMPLE	2025-07-07 19:21:00
438	4195052	CUMPLE	2025-07-07 19:21:00
439	4486689	CUMPLE	2025-07-07 19:21:00
440	2421903	NO CUMPLE	2025-07-07 19:21:00
441	2517542	NO CUMPLE	2025-07-07 19:21:00
442	2561168	NO CUMPLE	2025-07-07 19:21:00
443	5066080	CUMPLE	2025-07-07 19:21:00
444	5183782	CUMPLE	2025-07-07 19:21:00
445	1833468	NO CUMPLE	2025-07-07 19:21:00
446	4022426	NO CUMPLE	2025-07-07 19:21:00
447	4065500	NO CUMPLE	2025-07-07 19:21:00
448	4518307	CUMPLE	2025-07-07 19:21:00
449	5406885	CUMPLE	2025-07-07 19:21:00
450	5434259	CUMPLE	2025-07-07 19:21:00
451	4004969	NO CUMPLE	2025-07-07 19:21:00
452	4844299	CUMPLE	2025-07-07 19:21:00
453	5229865	CUMPLE	2025-07-07 19:21:00
454	5415815	CUMPLE	2025-07-07 19:21:00
455	2879081	CUMPLE	2025-07-07 19:21:00
456	2899305	CUMPLE	2025-07-07 19:21:00
457	4100018	CUMPLE	2025-07-07 19:21:00
458	4100035	CUMPLE	2025-07-07 19:21:00
459	4797195	CUMPLE	2025-07-07 19:21:00
460	2696895	NO CUMPLE	2025-07-07 19:21:00
461	2755808	NO CUMPLE	2025-07-07 19:21:00
462	2755809	NO CUMPLE	2025-07-07 19:21:00
463	4192768	NO CUMPLE	2025-07-07 19:21:00
464	4113547	NO CUMPLE	2025-07-07 19:21:00
465	5057382	NO CUMPLE	2025-07-07 19:21:00
466	5057383	NO CUMPLE	2025-07-07 19:21:00
467	5478988	CUMPLE	2025-07-07 19:21:00
468	4227110	NO CUMPLE	2025-07-07 19:21:00
469	4361604	NO CUMPLE	2025-07-07 19:21:00
470	5086574	CUMPLE	2025-07-07 19:21:00
471	5086576	NO CUMPLE	2025-07-07 19:21:00
472	5449687	CUMPLE	2025-07-07 19:21:00
473	5450047	CUMPLE	2025-07-07 19:21:00
474	5450049	CUMPLE	2025-07-07 19:21:00
475	4785737	CUMPLE	2025-07-07 19:21:00
476	4456574	CUMPLE	2025-07-07 19:21:00
477	4682113	CUMPLE	2025-07-07 19:21:00
478	4681432	CUMPLE	2025-07-07 19:21:00
479	2460958	CUMPLE	2025-07-07 19:21:00
480	2963002	CUMPLE	2025-07-07 19:21:00
481	4327529	CUMPLE	2025-07-07 19:21:00
482	4518516	CUMPLE	2025-07-07 19:21:00
483	2895865	CUMPLE	2025-07-07 19:21:00
484	5174732	NO CUMPLE	2025-07-07 19:21:00
485	5324238	CUMPLE	2025-07-07 19:21:00
486	4521015	NO CUMPLE	2025-07-07 19:21:00
487	2463402	NO CUMPLE	2025-07-07 19:21:00
488	2899654	CUMPLE	2025-07-07 19:21:00
489	2999304	CUMPLE	2025-07-07 19:21:00
490	4562963	CUMPLE	2025-07-07 19:21:00
491	4779206	CUMPLE	2025-07-07 19:21:00
492	4499069	CUMPLE	2025-07-07 19:21:00
493	4560170	NO CUMPLE	2025-07-07 19:21:00
494	5000454	NO CUMPLE	2025-07-07 19:21:00
495	5000456	NO CUMPLE	2025-07-07 19:21:00
496	2621302	NO CUMPLE	2025-07-07 19:21:00
497	2621304	NO CUMPLE	2025-07-07 19:21:00
498	2621305	NO CUMPLE	2025-07-07 19:21:00
499	2621306	NO CUMPLE	2025-07-07 19:21:00
500	4967048	NO CUMPLE	2025-07-07 19:21:00
501	2603983	CUMPLE	2025-07-07 19:21:00
502	4336789	NO CUMPLE	2025-07-07 19:21:00
503	4336790	NO CUMPLE	2025-07-07 19:21:00
504	4270095	NO CUMPLE	2025-07-07 19:21:00
505	4270096	NO CUMPLE	2025-07-07 19:21:00
506	4486484	NO CUMPLE	2025-07-07 19:21:00
507	4486486	NO CUMPLE	2025-07-07 19:21:00
508	4486487	NO CUMPLE	2025-07-07 19:21:00
509	2121848	NO CUMPLE	2025-07-07 19:21:00
510	2715239	NO CUMPLE	2025-07-07 19:21:00
511	2715240	CUMPLE	2025-07-07 19:21:00
512	4698038	NO CUMPLE	2025-07-07 19:21:00
513	2956256	CUMPLE	2025-07-07 19:21:00
514	2956257	CUMPLE	2025-07-07 19:21:00
515	4348304	NO CUMPLE	2025-07-07 19:21:00
516	4757562	CUMPLE	2025-07-07 19:21:00
517	5086582	CUMPLE	2025-07-07 19:21:00
518	2712377	NO CUMPLE	2025-07-07 19:21:00
519	4833698	NO CUMPLE	2025-07-07 19:21:00
520	4833700	NO CUMPLE	2025-07-07 19:21:00
521	4339470	NO CUMPLE	2025-07-07 19:21:00
522	4450052	NO CUMPLE	2025-07-07 19:21:00
523	2951116	CUMPLE	2025-07-07 19:21:00
524	4593210	NO CUMPLE	2025-07-07 19:21:00
525	4844719	CUMPLE	2025-07-07 19:21:00
526	4820473	NO CUMPLE	2025-07-07 19:21:00
527	4360160	CUMPLE	2025-07-07 19:21:00
528	4893825	CUMPLE	2025-07-07 19:21:00
529	5056936	NO CUMPLE	2025-07-07 19:21:00
530	5256078	CUMPLE	2025-07-07 19:21:00
531	5256082	CUMPLE	2025-07-07 19:21:00
532	5344145	CUMPLE	2025-07-07 19:21:00
533	5350007	CUMPLE	2025-07-07 19:21:00
534	5350008	CUMPLE	2025-07-07 19:21:00
535	5350010	CUMPLE	2025-07-07 19:21:00
536	5350011	CUMPLE	2025-07-07 19:21:00
537	5365814	CUMPLE	2025-07-07 19:21:00
538	5365816	CUMPLE	2025-07-07 19:21:00
539	5365817	CUMPLE	2025-07-07 19:21:00
540	4631291	CUMPLE	2025-07-07 19:21:00
541	2455335	NO CUMPLE	2025-07-07 19:21:00
542	2514843	NO CUMPLE	2025-07-07 19:21:00
543	4109217	NO CUMPLE	2025-07-07 19:21:00
544	2731162	CUMPLE	2025-07-07 19:21:00
545	2877793	NO CUMPLE	2025-07-07 19:21:00
546	4044134	CUMPLE	2025-07-07 19:21:00
547	4367520	CUMPLE	2025-07-07 19:21:00
548	4560169	NO CUMPLE	2025-07-07 19:21:00
549	4560171	NO CUMPLE	2025-07-07 19:21:00
550	4560172	NO CUMPLE	2025-07-07 19:21:00
551	4879967	CUMPLE	2025-07-07 19:21:00
552	4879968	CUMPLE	2025-07-07 19:21:00
553	4879969	CUMPLE	2025-07-07 19:21:00
554	4879970	CUMPLE	2025-07-07 19:21:00
555	2905406	NO CUMPLE	2025-07-07 19:21:00
556	5134385	CUMPLE	2025-07-07 19:21:00
557	5134388	NO CUMPLE	2025-07-07 19:21:00
558	4713688	NO CUMPLE	2025-07-07 19:21:00
559	2621308	NO CUMPLE	2025-07-07 19:21:00
560	2989401	NO CUMPLE	2025-07-07 19:21:00
561	4049609	NO CUMPLE	2025-07-07 19:21:00
562	4049610	NO CUMPLE	2025-07-07 19:21:00
563	4243479	CUMPLE	2025-07-07 19:21:00
564	4898419	NO CUMPLE	2025-07-07 19:21:00
565	5039098	NO CUMPLE	2025-07-07 19:21:00
566	5043901	CUMPLE	2025-07-07 19:21:00
567	2746024	NO CUMPLE	2025-07-07 19:21:00
568	4326473	NO CUMPLE	2025-07-07 19:21:00
569	4454544	CUMPLE	2025-07-07 19:21:00
570	4103694	CUMPLE	2025-07-07 19:21:00
571	4388558	CUMPLE	2025-07-07 19:21:00
572	4388559	CUMPLE	2025-07-07 19:21:00
573	4472682	NO CUMPLE	2025-07-07 19:21:00
574	4879455	CUMPLE	2025-07-07 19:21:00
575	5365004	CUMPLE	2025-07-07 19:21:00
576	5365005	CUMPLE	2025-07-07 19:21:00
577	5365006	CUMPLE	2025-07-07 19:21:00
578	5365794	CUMPLE	2025-07-07 19:21:00
579	5365795	CUMPLE	2025-07-07 19:21:00
580	4066973	NO CUMPLE	2025-07-07 19:21:00
581	4361576	NO CUMPLE	2025-07-07 19:21:00
582	4272519	NO CUMPLE	2025-07-07 19:21:00
583	2385645	NO CUMPLE	2025-07-07 19:21:00
584	2385646	NO CUMPLE	2025-07-07 19:21:00
585	4264175	CUMPLE	2025-07-07 19:21:00
586	4264180	CUMPLE	2025-07-07 19:21:00
587	4264192	CUMPLE	2025-07-07 19:21:00
588	5185121	CUMPLE	2025-07-07 19:21:00
589	1272141	NO CUMPLE	2025-07-07 19:21:00
590	1272142	NO CUMPLE	2025-07-07 19:21:00
591	4182746	NO CUMPLE	2025-07-07 19:21:00
592	4348298	NO CUMPLE	2025-07-07 19:21:00
593	4348300	CUMPLE	2025-07-07 19:21:00
594	5084558	NO CUMPLE	2025-07-07 19:21:00
595	5086580	CUMPLE	2025-07-07 19:21:00
596	5039693	NO CUMPLE	2025-07-07 19:21:00
597	4776660	CUMPLE	2025-07-07 19:21:00
598	4833702	NO CUMPLE	2025-07-07 19:21:00
599	5064403	CUMPLE	2025-07-07 19:21:00
600	5436284	CUMPLE	2025-07-07 19:21:00
601	4547579	NO CUMPLE	2025-07-07 19:21:00
602	2341938	NO CUMPLE	2025-07-07 19:21:00
603	2621352	CUMPLE	2025-07-07 19:21:00
604	2621353	CUMPLE	2025-07-07 19:21:00
605	2715552	NO CUMPLE	2025-07-07 19:21:00
606	4451184	NO CUMPLE	2025-07-07 19:21:00
607	5399773	CUMPLE	2025-07-07 19:21:00
608	4093969	NO CUMPLE	2025-07-07 19:21:00
609	4436974	CUMPLE	2025-07-07 19:21:00
610	4768151	CUMPLE	2025-07-07 19:21:00
611	2970126	NO CUMPLE	2025-07-07 19:21:00
612	4493658	NO CUMPLE	2025-07-07 19:21:00
613	5399063	CUMPLE	2025-07-07 19:21:00
614	2990058	CUMPLE	2025-07-07 19:21:00
615	4844300	NO CUMPLE	2025-07-07 19:21:00
616	4333540	CUMPLE	2025-07-07 19:21:00
617	5278804	CUMPLE	2025-07-07 19:21:00
618	5284372	CUMPLE	2025-07-07 19:21:00
619	2941536	CUMPLE	2025-07-07 19:21:00
620	2455337	NO CUMPLE	2025-07-07 19:21:00
621	5002489	NO CUMPLE	2025-07-07 19:21:00
622	2731160	CUMPLE	2025-07-07 19:21:00
623	4146152	NO CUMPLE	2025-07-07 19:21:00
624	4713651	CUMPLE	2025-07-07 19:21:00
625	4713652	CUMPLE	2025-07-07 19:21:00
626	2621307	CUMPLE	2025-07-07 19:21:00
627	4898420	NO CUMPLE	2025-07-07 19:21:00
628	4909568	CUMPLE	2025-07-07 19:21:00
629	4967047	NO CUMPLE	2025-07-07 19:21:00
630	4967050	NO CUMPLE	2025-07-07 19:21:00
631	4995766	NO CUMPLE	2025-07-07 19:21:00
632	5004534	NO CUMPLE	2025-07-07 19:21:00
633	5411338	CUMPLE	2025-07-07 19:21:00
634	5411339	CUMPLE	2025-07-07 19:21:00
635	4301983	NO CUMPLE	2025-07-07 19:21:00
636	4560118	NO CUMPLE	2025-07-07 19:21:00
637	4308282	NO CUMPLE	2025-07-07 19:21:00
638	4308284	NO CUMPLE	2025-07-07 19:21:00
639	5417488	CUMPLE	2025-07-07 19:21:00
640	5417691	CUMPLE	2025-07-07 19:21:00
641	4819794	NO CUMPLE	2025-07-07 19:21:00
642	4067286	NO CUMPLE	2025-07-07 19:21:00
643	4531442	CUMPLE	2025-07-07 19:21:00
644	4425515	CUMPLE	2025-07-07 19:21:00
645	2999423	NO CUMPLE	2025-07-07 19:21:00
646	4271877	NO CUMPLE	2025-07-07 19:21:00
647	4290360	NO CUMPLE	2025-07-07 19:21:00
648	2959113	CUMPLE	2025-07-07 19:21:00
649	4348306	NO CUMPLE	2025-07-07 19:21:00
650	4651998	NO CUMPLE	2025-07-07 19:21:00
651	2141856	CUMPLE	2025-07-07 19:21:00
652	4170016	NO CUMPLE	2025-07-07 19:21:00
653	5004757	NO CUMPLE	2025-07-07 19:21:00
654	4463655	CUMPLE	2025-07-07 19:21:00
655	4339474	NO CUMPLE	2025-07-07 19:21:00
656	4448194	NO CUMPLE	2025-07-07 19:21:00
657	2967782	CUMPLE	2025-07-07 19:21:00
658	4807075	NO CUMPLE	2025-07-07 19:21:00
659	4313875	NO CUMPLE	2025-07-07 19:21:00
660	5486174	CUMPLE	2025-07-07 19:21:00
661	5486176	CUMPLE	2025-07-07 19:21:00
662	5098976	NO CUMPLE	2025-07-07 19:21:00
663	2972858	NO CUMPLE	2025-07-07 19:21:00
664	2648190	NO CUMPLE	2025-07-07 19:21:00
665	2111280	NO CUMPLE	2025-07-07 19:21:00
666	4781337	NO CUMPLE	2025-07-07 19:21:00
667	4451856	NO CUMPLE	2025-07-07 19:21:00
668	2711073	NO CUMPLE	2025-07-07 19:21:00
669	2990055	NO CUMPLE	2025-07-07 19:21:00
670	414649	NO CUMPLE	2025-07-07 19:21:00
671	414648	NO CUMPLE	2025-07-07 19:21:00
672	4804186	NO CUMPLE	2025-07-07 19:21:00
673	4804184	NO CUMPLE	2025-07-07 19:21:00
674	5383755	CUMPLE	2025-07-07 19:21:00
675	5383754	CUMPLE	2025-07-07 19:21:00
676	5508355	CUMPLE	2025-07-07 19:21:00
677	5508358	CUMPLE	2025-07-07 19:21:00
678	2398060	CUMPLE	2025-07-07 19:21:00
679	2398071	CUMPLE	2025-07-07 19:21:00
680	4844290	CUMPLE	2025-07-07 19:21:00
681	4844289	CUMPLE	2025-07-07 19:21:00
682	4777409	CUMPLE	2025-07-07 19:21:00
683	5145645	CUMPLE	2025-07-07 19:21:00
684	5145647	CUMPLE	2025-07-07 19:21:00
685	2941541	CUMPLE	2025-07-07 19:21:00
686	4404589	NO CUMPLE	2025-07-07 19:21:00
687	4404587	NO CUMPLE	2025-07-07 19:21:00
688	4404586	NO CUMPLE	2025-07-07 19:21:00
689	5045535	CUMPLE	2025-07-07 19:21:00
690	2504729	NO CUMPLE	2025-07-07 19:21:00
691	2504727	NO CUMPLE	2025-07-07 19:21:00
692	2504726	NO CUMPLE	2025-07-07 19:21:00
693	2504725	NO CUMPLE	2025-07-07 19:21:00
694	4797388	CUMPLE	2025-07-07 19:21:00
695	5255929	CUMPLE	2025-07-07 19:21:00
696	5281037	CUMPLE	2025-07-07 19:21:00
697	4797389	CUMPLE	2025-07-07 19:21:00
698	4797391	CUMPLE	2025-07-07 19:21:00
699	4806993	NO CUMPLE	2025-07-07 19:21:00
700	4797393	NO CUMPLE	2025-07-07 19:21:00
701	4301984	NO CUMPLE	2025-07-07 19:21:00
702	4879990	NO CUMPLE	2025-07-07 19:21:00
703	2881251	NO CUMPLE	2025-07-07 19:21:00
704	4905565	CUMPLE	2025-07-07 19:21:00
705	4984797	CUMPLE	2025-07-07 19:21:00
706	5286358	NO CUMPLE	2025-07-07 19:21:00
707	5286359	NO CUMPLE	2025-07-07 19:21:00
708	5563180	CUMPLE	2025-07-07 19:21:00
709	4852773	CUMPLE	2025-07-07 19:21:00
710	5013777	CUMPLE	2025-07-07 19:21:00
711	2696867	NO CUMPLE	2025-07-07 19:21:00
712	2455323	NO CUMPLE	2025-07-07 19:21:00
713	2714804	CUMPLE	2025-07-07 19:21:00
714	2474953	NO CUMPLE	2025-07-07 19:21:00
715	2989402	NO CUMPLE	2025-07-07 19:21:00
716	4243481	NO CUMPLE	2025-07-07 19:21:00
717	5005697	NO CUMPLE	2025-07-07 19:21:00
718	2518043	NO CUMPLE	2025-07-07 19:21:00
719	2472593	CUMPLE	2025-07-07 19:21:00
720	4192902	NO CUMPLE	2025-07-07 19:21:00
721	4560148	NO CUMPLE	2025-07-07 19:21:00
722	4791231	NO CUMPLE	2025-07-07 19:21:00
723	5063923	NO CUMPLE	2025-07-07 19:21:00
724	5063925	NO CUMPLE	2025-07-07 19:21:00
725	5063927	NO CUMPLE	2025-07-07 19:21:00
726	534494	NO CUMPLE	2025-07-07 19:21:00
727	4272515	CUMPLE	2025-07-07 19:21:00
728	4272522	CUMPLE	2025-07-07 19:21:00
729	2726074	CUMPLE	2025-07-07 19:21:00
730	2726079	CUMPLE	2025-07-07 19:21:00
731	4313946	NO CUMPLE	2025-07-07 19:21:00
732	4313949	NO CUMPLE	2025-07-07 19:21:00
733	4484573	NO CUMPLE	2025-07-07 19:21:00
734	5334008	CUMPLE	2025-07-07 19:21:00
735	5334009	CUMPLE	2025-07-07 19:21:00
736	2621349	CUMPLE	2025-07-07 19:21:00
737	2621350	CUMPLE	2025-07-07 19:21:00
738	4808566	NO CUMPLE	2025-07-07 19:21:00
739	5098974	NO CUMPLE	2025-07-07 19:21:00
740	5445485	NO CUMPLE	2025-07-07 19:21:00
741	5215440	CUMPLE	2025-07-07 19:21:00
742	5215441	CUMPLE	2025-07-07 19:21:00
743	2706588	NO CUMPLE	2025-07-07 19:21:00
744	1681557	NO CUMPLE	2025-07-07 19:21:00
745	4271417	NO CUMPLE	2025-07-07 19:21:00
746	4333539	CUMPLE	2025-07-07 19:21:00
747	4549672	CUMPLE	2025-07-07 19:21:00
748	5104613	NO CUMPLE	2025-07-07 19:21:00
749	5255934	CUMPLE	2025-07-07 19:21:00
750	5278821	CUMPLE	2025-07-07 19:21:00
751	5278822	CUMPLE	2025-07-07 19:21:00
752	5284374	CUMPLE	2025-07-07 19:21:00
753	5284376	CUMPLE	2025-07-07 19:21:00
754	5418033	CUMPLE	2025-07-07 19:21:00
755	5528650	CUMPLE	2025-07-07 19:21:00
756	5531640	CUMPLE	2025-07-07 19:21:00
757	5532376	CUMPLE	2025-07-07 19:21:00
758	5532819	CUMPLE	2025-07-07 19:21:00
759	5533612	CUMPLE	2025-07-07 19:21:00
760	4964787	CUMPLE	2025-07-07 19:21:00
761	2575588	NO CUMPLE	2025-07-07 19:21:00
762	2899683	CUMPLE	2025-07-07 19:21:00
763	2610995	CUMPLE	2025-07-07 19:21:00
764	4146154	NO CUMPLE	2025-07-07 19:21:00
765	4146155	NO CUMPLE	2025-07-07 19:21:00
766	4527593	CUMPLE	2025-07-07 19:21:00
767	4397818	NO CUMPLE	2025-07-07 19:21:00
768	4397819	NO CUMPLE	2025-07-07 19:21:00
769	4397821	NO CUMPLE	2025-07-07 19:21:00
770	4397822	NO CUMPLE	2025-07-07 19:21:00
771	4757326	CUMPLE	2025-07-07 19:21:00
772	4757327	CUMPLE	2025-07-07 19:21:00
773	4757329	CUMPLE	2025-07-07 19:21:00
774	4878857	CUMPLE	2025-07-07 19:21:00
775	4977241	NO CUMPLE	2025-07-07 19:21:00
776	5411336	CUMPLE	2025-07-07 19:21:00
777	5411342	CUMPLE	2025-07-07 19:21:00
778	2630034	NO CUMPLE	2025-07-07 19:21:00
779	4454540	NO CUMPLE	2025-07-07 19:21:00
780	4454542	NO CUMPLE	2025-07-07 19:21:00
781	4228802	NO CUMPLE	2025-07-07 19:21:00
782	4308279	NO CUMPLE	2025-07-07 19:21:00
783	4308280	NO CUMPLE	2025-07-07 19:21:00
784	4308281	NO CUMPLE	2025-07-07 19:21:00
785	4463314	NO CUMPLE	2025-07-07 19:21:00
786	4695912	CUMPLE	2025-07-07 19:21:00
787	2747954	NO CUMPLE	2025-07-07 19:21:00
788	2747958	NO CUMPLE	2025-07-07 19:21:00
789	4027247	CUMPLE	2025-07-07 19:21:00
790	4105385	NO CUMPLE	2025-07-07 19:21:00
791	4308508	NO CUMPLE	2025-07-07 19:21:00
792	5416013	CUMPLE	2025-07-07 19:21:00
793	5416015	CUMPLE	2025-07-07 19:21:00
794	5417490	CUMPLE	2025-07-07 19:21:00
795	5417690	CUMPLE	2025-07-07 19:21:00
796	4789467	NO CUMPLE	2025-07-07 19:21:00
797	4997642	NO CUMPLE	2025-07-07 19:21:00
798	4997643	NO CUMPLE	2025-07-07 19:21:00
799	4997644	NO CUMPLE	2025-07-07 19:21:00
800	4997646	NO CUMPLE	2025-07-07 19:21:00
801	4033284	NO CUMPLE	2025-07-07 19:21:00
802	4193720	CUMPLE	2025-07-07 19:21:00
803	4193722	CUMPLE	2025-07-07 19:21:00
804	5450043	CUMPLE	2025-07-07 19:21:00
805	4009640	CUMPLE	2025-07-07 19:21:00
806	4776654	CUMPLE	2025-07-07 19:21:00
807	5450405	CUMPLE	2025-07-07 19:21:00
808	5450409	CUMPLE	2025-07-07 19:21:00
809	5450411	CUMPLE	2025-07-07 19:21:00
810	2126331	NO CUMPLE	2025-07-07 19:21:00
811	2180978	CUMPLE	2025-07-07 19:21:00
812	2669062	NO CUMPLE	2025-07-07 19:21:00
813	2691853	NO CUMPLE	2025-07-07 19:21:00
814	5406884	CUMPLE	2025-07-07 19:21:00
815	2485008	NO CUMPLE	2025-07-07 19:21:00
816	2455325	NO CUMPLE	2025-07-07 19:21:00
817	4436785	NO CUMPLE	2025-07-07 19:21:00
818	2603982	CUMPLE	2025-07-07 19:21:00
819	4227111	NO CUMPLE	2025-07-07 19:21:00
820	4270127	NO CUMPLE	2025-07-07 19:21:00
821	2500635	NO CUMPLE	2025-07-07 19:21:00
822	4271868	CUMPLE	2025-07-07 19:21:00
823	2961305	CUMPLE	2025-07-07 19:21:00
824	4698560	CUMPLE	2025-07-07 19:21:00
825	4895463	CUMPLE	2025-07-07 19:21:00
826	5294535	CUMPLE	2025-07-07 19:21:00
827	5350399	CUMPLE	2025-07-07 19:21:00
828	5419516	CUMPLE	2025-07-07 19:21:00
829	4298569	CUMPLE	2025-07-07 19:21:00
830	4047154	CUMPLE	2025-07-07 19:21:00
831	4559615	CUMPLE	2025-07-07 19:21:00
832	655151	CUMPLE	2025-07-07 19:21:00
833	4264491	CUMPLE	2025-07-07 19:21:00
834	4336362	CUMPLE	2025-07-07 19:21:00
835	4344007	CUMPLE	2025-07-07 19:21:00
836	4566150	CUMPLE	2025-07-07 19:21:00
837	4851194	CUMPLE	2025-07-07 19:21:00
838	5475384	CUMPLE	2025-07-07 19:21:00
839	4012156	CUMPLE	2025-07-07 19:21:00
840	2454973	CUMPLE	2025-07-07 19:21:00
841	2455267	CUMPLE	2025-07-07 19:21:00
842	2455271	CUMPLE	2025-07-07 19:21:00
843	2611000	CUMPLE	2025-07-07 19:21:00
844	4647024	CUMPLE	2025-07-07 19:21:00
845	2645273	CUMPLE	2025-07-07 19:21:00
846	2731166	CUMPLE	2025-07-07 19:21:00
847	2747726	CUMPLE	2025-07-07 19:21:00
848	2942440	CUMPLE	2025-07-07 19:21:00
849	4116235	CUMPLE	2025-07-07 19:21:00
850	5000452	CUMPLE	2025-07-07 19:21:00
851	2342035	CUMPLE	2025-07-07 19:21:00
852	4469474	CUMPLE	2025-07-07 19:21:00
853	4713687	CUMPLE	2025-07-07 19:21:00
854	4146993	CUMPLE	2025-07-07 19:21:00
855	4878853	CUMPLE	2025-07-07 19:21:00
856	4878854	CUMPLE	2025-07-07 19:21:00
857	4967046	CUMPLE	2025-07-07 19:21:00
858	4995154	CUMPLE	2025-07-07 19:21:00
859	4995155	CUMPLE	2025-07-07 19:21:00
860	4995156	CUMPLE	2025-07-07 19:21:00
861	5008909	CUMPLE	2025-07-07 19:21:00
862	5011490	CUMPLE	2025-07-07 19:21:00
863	5044686	CUMPLE	2025-07-07 19:21:00
864	5104621	CUMPLE	2025-07-07 19:21:00
865	4349758	CUMPLE	2025-07-07 19:21:00
866	1033684	CUMPLE	2025-07-07 19:21:00
867	4530606	CUMPLE	2025-07-07 19:21:00
868	2603985	CUMPLE	2025-07-07 19:21:00
869	4388557	CUMPLE	2025-07-07 19:21:00
870	4472683	CUMPLE	2025-07-07 19:21:00
871	5000336	CUMPLE	2025-07-07 19:21:00
872	5000337	CUMPLE	2025-07-07 19:21:00
873	1779333	CUMPLE	2025-07-07 19:21:00
874	1779334	CUMPLE	2025-07-07 19:21:00
875	2654299	CUMPLE	2025-07-07 19:21:00
876	1207621	CUMPLE	2025-07-07 19:21:00
877	1207622	CUMPLE	2025-07-07 19:21:00
878	2380817	CUMPLE	2025-07-07 19:21:00
879	2380819	CUMPLE	2025-07-07 19:21:00
880	4361577	CUMPLE	2025-07-07 19:21:00
881	4361589	CUMPLE	2025-07-07 19:21:00
882	4361606	CUMPLE	2025-07-07 19:21:00
883	4193721	CUMPLE	2025-07-07 19:21:00
884	4757503	CUMPLE	2025-07-07 19:21:00
885	1840227	CUMPLE	2025-07-07 19:21:00
886	1840229	CUMPLE	2025-07-07 19:21:00
887	2651997	CUMPLE	2025-07-07 19:21:00
888	2954996	CUMPLE	2025-07-07 19:21:00
889	4044150	CUMPLE	2025-07-07 19:21:00
890	4044151	CUMPLE	2025-07-07 19:21:00
891	4044152	CUMPLE	2025-07-07 19:21:00
892	4044153	CUMPLE	2025-07-07 19:21:00
893	4273716	CUMPLE	2025-07-07 19:21:00
894	4273722	CUMPLE	2025-07-07 19:21:00
895	4425235	CUMPLE	2025-07-07 19:21:00
896	4747572	CUMPLE	2025-07-07 19:21:00
897	5004756	CUMPLE	2025-07-07 19:21:00
898	5101432	CUMPLE	2025-07-07 19:21:00
899	4448192	CUMPLE	2025-07-07 19:21:00
900	4448193	CUMPLE	2025-07-07 19:21:00
901	4756882	CUMPLE	2025-07-07 19:21:00
902	2621348	CUMPLE	2025-07-07 19:21:00
903	2621351	CUMPLE	2025-07-07 19:21:00
904	2500634	CUMPLE	2025-07-07 19:21:00
905	2981227	CUMPLE	2025-07-07 19:21:00
906	4933895	CUMPLE	2025-07-07 19:21:00
907	4933897	CUMPLE	2025-07-07 19:21:00
908	4933898	CUMPLE	2025-07-07 19:21:00
909	5074498	CUMPLE	2025-07-07 19:21:00
910	4108976	CUMPLE	2025-07-07 19:21:00
911	4303771	CUMPLE	2025-07-07 19:21:00
912	4303772	CUMPLE	2025-07-07 19:21:00
913	4518515	CUMPLE	2025-07-07 19:21:00
914	2975849	CUMPLE	2025-07-07 19:21:00
915	2667418	CUMPLE	2025-07-07 19:21:00
916	5165502	NO CUMPLE	2025-07-07 19:21:00
917	5024226	CUMPLE	2025-07-07 19:21:00
918	5255932	CUMPLE	2025-07-07 19:21:00
919	5255933	CUMPLE	2025-07-07 19:21:00
920	2309944	CUMPLE	2025-07-07 19:21:00
921	2225716	CUMPLE	2025-07-07 19:21:00
922	4550683	CUMPLE	2025-07-07 19:21:00
923	4985721	CUMPLE	2025-07-07 19:21:00
924	5045372	CUMPLE	2025-07-07 19:21:00
925	5367309	CUMPLE	2025-07-07 19:21:00
926	2455321	NO CUMPLE	2025-07-07 19:21:00
927	2617513	NO CUMPLE	2025-07-07 19:21:00
928	2900266	NO CUMPLE	2025-07-07 19:21:00
929	2755807	NO CUMPLE	2025-07-07 19:21:00
930	4994777	CUMPLE	2025-07-07 19:21:00
931	4994778	CUMPLE	2025-07-07 19:21:00
932	4465489	NO CUMPLE	2025-07-07 19:21:00
933	4761349	CUMPLE	2025-07-07 19:21:00
934	4761351	CUMPLE	2025-07-07 19:21:00
935	4713658	CUMPLE	2025-07-07 19:21:00
936	4271634	NO CUMPLE	2025-07-07 19:21:00
937	5043898	CUMPLE	2025-07-07 19:21:00
938	5043900	CUMPLE	2025-07-07 19:21:00
939	5055363	NO CUMPLE	2025-07-07 19:21:00
940	5055364	CUMPLE	2025-07-07 19:21:00
941	5055365	CUMPLE	2025-07-07 19:21:00
942	5055381	CUMPLE	2025-07-07 19:21:00
943	5153875	NO CUMPLE	2025-07-07 19:21:00
944	4525727	NO CUMPLE	2025-07-07 19:21:00
945	4545899	NO CUMPLE	2025-07-07 19:21:00
946	4458015	NO CUMPLE	2025-07-07 19:21:00
947	2470290	NO CUMPLE	2025-07-07 19:21:00
948	2470291	NO CUMPLE	2025-07-07 19:21:00
949	5057461	NO CUMPLE	2025-07-07 19:21:00
950	4749133	NO CUMPLE	2025-07-07 19:21:00
951	4228775	NO CUMPLE	2025-07-07 19:21:00
952	4997386	CUMPLE	2025-07-07 19:21:00
953	4447274	CUMPLE	2025-07-07 19:21:00
954	4567322	NO CUMPLE	2025-07-07 19:21:00
955	2657114	NO CUMPLE	2025-07-07 19:21:00
956	4033286	NO CUMPLE	2025-07-07 19:21:00
957	5058149	NO CUMPLE	2025-07-07 19:21:00
958	2126335	NO CUMPLE	2025-07-07 19:21:00
959	4066076	NO CUMPLE	2025-07-07 19:21:00
960	2765851	CUMPLE	2025-07-07 19:21:00
961	1796820	CUMPLE	2025-07-07 19:21:00
962	5405382	CUMPLE	2025-07-07 19:21:00
963	2695479	CUMPLE	2025-07-07 19:21:00
964	2695477	CUMPLE	2025-07-07 19:21:00
965	2695475	CUMPLE	2025-07-07 19:21:00
966	2695473	CUMPLE	2025-07-07 19:21:00
967	2695465	CUMPLE	2025-07-07 19:21:00
968	4504051	CUMPLE	2025-07-07 19:21:00
969	2467687	CUMPLE	2025-07-07 19:21:00
970	4006186	CUMPLE	2025-07-07 19:21:00
971	4335960	CUMPLE	2025-07-07 19:21:00
972	4002013	CUMPLE	2025-07-07 19:21:00
973	4097233	CUMPLE	2025-07-07 19:21:00
974	4097226	CUMPLE	2025-07-07 19:21:00
975	4321902	NO CUMPLE	2025-07-07 19:21:00
976	4321901	NO CUMPLE	2025-07-07 19:21:00
977	4321900	NO CUMPLE	2025-07-07 19:21:00
978	4321899	NO CUMPLE	2025-07-07 19:21:00
979	4321895	NO CUMPLE	2025-07-07 19:21:00
980	4094321	NO CUMPLE	2025-07-07 19:21:00
981	4094320	CUMPLE	2025-07-07 19:21:00
982	4094318	NO CUMPLE	2025-07-07 19:21:00
983	4094281	NO CUMPLE	2025-07-07 19:21:00
984	4094280	NO CUMPLE	2025-07-07 19:21:00
985	2778465	CUMPLE	2025-07-07 19:21:00
986	2778464	NO CUMPLE	2025-07-07 19:21:00
987	2778463	CUMPLE	2025-07-07 19:21:00
988	4097230	CUMPLE	2025-07-07 19:21:00
989	4097229	CUMPLE	2025-07-07 19:21:00
990	4097232	CUMPLE	2025-07-07 19:21:00
991	4097231	CUMPLE	2025-07-07 19:21:00
992	4925551	NO CUMPLE	2025-07-07 19:21:00
993	2699246	CUMPLE	2025-07-07 19:21:00
994	2699245	CUMPLE	2025-07-07 19:21:00
995	2699244	CUMPLE	2025-07-07 19:21:00
996	2699243	CUMPLE	2025-07-07 19:21:00
997	2699241	CUMPLE	2025-07-07 19:21:00
998	2920397	CUMPLE	2025-07-07 19:21:00
999	2920395	CUMPLE	2025-07-07 19:21:00
1000	2920394	CUMPLE	2025-07-07 19:21:00
1001	2920393	CUMPLE	2025-07-07 19:21:00
1002	2432299	NO CUMPLE	2025-07-07 19:21:00
1003	2432298	NO CUMPLE	2025-07-07 19:21:00
1004	383093	NO CUMPLE	2025-07-07 19:21:00
1005	2778467	NO CUMPLE	2025-07-07 19:21:00
1006	2191618	NO CUMPLE	2025-07-07 19:21:00
1007	2191613	NO CUMPLE	2025-07-07 19:21:00
1008	5117915	NO CUMPLE	2025-07-07 19:21:00
1009	2765593	NO CUMPLE	2025-07-07 19:21:00
1010	2765592	NO CUMPLE	2025-07-07 19:21:00
1011	2765591	NO CUMPLE	2025-07-07 19:21:00
1012	2765590	NO CUMPLE	2025-07-07 19:21:00
1013	4163887	NO CUMPLE	2025-07-07 19:21:00
1014	4163886	NO CUMPLE	2025-07-07 19:21:00
1015	4163885	NO CUMPLE	2025-07-07 19:21:00
1016	4163888	NO CUMPLE	2025-07-07 19:21:00
1017	4163882	NO CUMPLE	2025-07-07 19:21:00
1018	2758193	CUMPLE	2025-07-07 19:21:00
1019	2500812	NO CUMPLE	2025-07-07 19:21:00
1020	2500811	NO CUMPLE	2025-07-07 19:21:00
1021	2500810	NO CUMPLE	2025-07-07 19:21:00
1022	2500809	NO CUMPLE	2025-07-07 19:21:00
1023	2500807	NO CUMPLE	2025-07-07 19:21:00
1024	2379604	NO CUMPLE	2025-07-07 19:21:00
1025	2379603	NO CUMPLE	2025-07-07 19:21:00
1026	2379602	NO CUMPLE	2025-07-07 19:21:00
1027	2379601	NO CUMPLE	2025-07-07 19:21:00
1028	2379600	NO CUMPLE	2025-07-07 19:21:00
1029	2379599	NO CUMPLE	2025-07-07 19:21:00
1030	2745753	NO CUMPLE	2025-07-07 19:21:00
1031	2745751	NO CUMPLE	2025-07-07 19:21:00
1032	4308501	NO CUMPLE	2025-07-07 19:21:00
1033	4308500	NO CUMPLE	2025-07-07 19:21:00
1034	4308498	NO CUMPLE	2025-07-07 19:21:00
1035	4308497	NO CUMPLE	2025-07-07 19:21:00
1036	4308496	NO CUMPLE	2025-07-07 19:21:00
1037	4925307	NO CUMPLE	2025-07-07 19:21:00
1038	4925306	NO CUMPLE	2025-07-07 19:21:00
1039	4925305	NO CUMPLE	2025-07-07 19:21:00
1040	4925304	NO CUMPLE	2025-07-07 19:21:00
1041	4560146	NO CUMPLE	2025-07-07 19:21:00
1042	4560145	NO CUMPLE	2025-07-07 19:21:00
1043	4560144	NO CUMPLE	2025-07-07 19:21:00
1044	4560143	NO CUMPLE	2025-07-07 19:21:00
1045	4560142	NO CUMPLE	2025-07-07 19:21:00
1046	4560141	NO CUMPLE	2025-07-07 19:21:00
1047	4549011	NO CUMPLE	2025-07-07 19:21:00
1048	4549009	NO CUMPLE	2025-07-07 19:21:00
1049	4549007	NO CUMPLE	2025-07-07 19:21:00
1050	4549005	NO CUMPLE	2025-07-07 19:21:00
1051	4432243	NO CUMPLE	2025-07-07 19:21:00
1052	4432240	NO CUMPLE	2025-07-07 19:21:00
1053	4432239	NO CUMPLE	2025-07-07 19:21:00
1054	4432237	NO CUMPLE	2025-07-07 19:21:00
1055	4194021	NO CUMPLE	2025-07-07 19:21:00
1056	4194020	NO CUMPLE	2025-07-07 19:21:00
1057	4194016	NO CUMPLE	2025-07-07 19:21:00
1058	4194015	NO CUMPLE	2025-07-07 19:21:00
1059	2547189	NO CUMPLE	2025-07-07 19:21:00
1060	2547186	NO CUMPLE	2025-07-07 19:21:00
1061	2547185	NO CUMPLE	2025-07-07 19:21:00
1062	4925308	CUMPLE	2025-07-07 19:21:00
1063	2547187	NO CUMPLE	2025-07-07 19:21:00
1064	2547184	NO CUMPLE	2025-07-07 19:21:00
1065	338286	NO CUMPLE	2025-07-07 19:21:00
1066	2501394	NO CUMPLE	2025-07-07 19:21:00
1067	4560179	NO CUMPLE	2025-07-07 19:21:00
1068	5255922	CUMPLE	2025-07-07 19:21:00
1069	5255921	CUMPLE	2025-07-07 19:21:00
1070	5255920	CUMPLE	2025-07-07 19:21:00
1071	5255918	CUMPLE	2025-07-07 19:21:00
1072	5255917	CUMPLE	2025-07-07 19:21:00
1073	5255916	CUMPLE	2025-07-07 19:21:00
1074	4560181	NO CUMPLE	2025-07-07 19:21:00
1075	4560180	NO CUMPLE	2025-07-07 19:21:00
1076	4560178	NO CUMPLE	2025-07-07 19:21:00
1077	4560177	NO CUMPLE	2025-07-07 19:21:00
1078	2730472	CUMPLE	2025-07-07 19:21:00
1079	2730470	CUMPLE	2025-07-07 19:21:00
1080	2730469	CUMPLE	2025-07-07 19:21:00
1081	2730468	CUMPLE	2025-07-07 19:21:00
1082	2730467	CUMPLE	2025-07-07 19:21:00
1083	5419819	CUMPLE	2025-07-07 19:21:00
1084	5165125	CUMPLE	2025-07-07 19:21:00
1085	5165123	CUMPLE	2025-07-07 19:21:00
1086	5165122	CUMPLE	2025-07-07 19:21:00
1087	5165121	CUMPLE	2025-07-07 19:21:00
1088	5165120	CUMPLE	2025-07-07 19:21:00
1089	4701229	CUMPLE	2025-07-07 19:21:00
1090	4701228	CUMPLE	2025-07-07 19:21:00
1091	4701227	CUMPLE	2025-07-07 19:21:00
1092	4701225	CUMPLE	2025-07-07 19:21:00
1093	4701217	CUMPLE	2025-07-07 19:21:00
1094	4701216	CUMPLE	2025-07-07 19:21:00
1095	4701215	CUMPLE	2025-07-07 19:21:00
1096	2889231	NO CUMPLE	2025-07-07 19:21:00
1097	2889230	NO CUMPLE	2025-07-07 19:21:00
1098	2889229	NO CUMPLE	2025-07-07 19:21:00
1099	2889228	NO CUMPLE	2025-07-07 19:21:00
1100	5508354	CUMPLE	2025-07-07 19:21:00
1101	2422435	NO CUMPLE	2025-07-07 19:21:00
1102	2422429	NO CUMPLE	2025-07-07 19:21:00
1103	2422433	NO CUMPLE	2025-07-07 19:21:00
1104	2730760	CUMPLE	2025-07-07 19:21:00
1105	2730756	CUMPLE	2025-07-07 19:21:00
1106	2730754	CUMPLE	2025-07-07 19:21:00
1107	2730752	CUMPLE	2025-07-07 19:21:00
1108	4327058	CUMPLE	2025-07-07 19:21:00
1109	4243368	NO CUMPLE	2025-07-07 19:21:00
1110	4243367	NO CUMPLE	2025-07-07 19:21:00
1111	5264947	CUMPLE	2025-07-07 19:21:00
1112	5264943	CUMPLE	2025-07-07 19:21:00
1113	5264940	CUMPLE	2025-07-07 19:21:00
1114	5264945	CUMPLE	2025-07-07 19:21:00
1115	4925481	CUMPLE	2025-07-07 19:21:00
1116	4281885	CUMPLE	2025-07-07 19:21:00
1117	4281882	CUMPLE	2025-07-07 19:21:00
1118	4281881	CUMPLE	2025-07-07 19:21:00
1119	4281879	CUMPLE	2025-07-07 19:21:00
1120	4281877	CUMPLE	2025-07-07 19:21:00
1121	4341834	CUMPLE	2025-07-07 19:21:00
1122	5436273	CUMPLE	2025-07-07 19:21:00
1123	5436272	CUMPLE	2025-07-07 19:21:00
1124	5436271	CUMPLE	2025-07-07 19:21:00
1125	5436270	CUMPLE	2025-07-07 19:21:00
1126	5436269	CUMPLE	2025-07-07 19:21:00
1127	5436268	CUMPLE	2025-07-07 19:21:00
1128	4287788	NO CUMPLE	2025-07-07 19:21:00
1129	4287787	NO CUMPLE	2025-07-07 19:21:00
1130	4287785	NO CUMPLE	2025-07-07 19:21:00
1131	5042751	CUMPLE	2025-07-07 19:21:00
1132	5042750	CUMPLE	2025-07-07 19:21:00
1133	5042749	CUMPLE	2025-07-07 19:21:00
1134	5042748	CUMPLE	2025-07-07 19:21:00
1135	5042747	CUMPLE	2025-07-07 19:21:00
1136	5042746	CUMPLE	2025-07-07 19:21:00
1137	5042745	CUMPLE	2025-07-07 19:21:00
1138	5165124	CUMPLE	2025-07-07 19:21:00
1139	4175975	CUMPLE	2025-07-07 19:21:00
1140	4233000	CUMPLE	2025-07-07 19:21:00
1141	4604432	CUMPLE	2025-07-07 19:21:00
1142	4897211	NO CUMPLE	2025-07-07 19:21:00
1143	4897214	CUMPLE	2025-07-07 19:21:00
1144	5066499	CUMPLE	2025-07-07 19:21:00
1145	5419791	CUMPLE	2025-07-07 19:21:00
1146	1128495	NO CUMPLE	2025-07-07 19:21:00
1147	2989804	CUMPLE	2025-07-07 19:21:00
1148	4001607	CUMPLE	2025-07-07 19:21:00
1149	4335209	CUMPLE	2025-07-07 19:21:00
1150	5205742	CUMPLE	2025-07-07 19:21:00
1151	4146153	NO CUMPLE	2025-07-07 19:21:00
1152	4215679	CUMPLE	2025-07-07 19:21:00
1153	5400029	CUMPLE	2025-07-07 19:21:00
1154	4454537	NO CUMPLE	2025-07-07 19:21:00
1155	5414683	NO CUMPLE	2025-07-07 19:21:00
1156	4542621	NO CUMPLE	2025-07-07 19:21:00
1157	4542623	NO CUMPLE	2025-07-07 19:21:00
1158	4797350	NO CUMPLE	2025-07-07 19:21:00
1159	4408714	NO CUMPLE	2025-07-07 19:21:00
1160	840210	NO CUMPLE	2025-07-07 19:21:00
1161	1539895	NO CUMPLE	2025-07-07 19:21:00
1162	4264181	NO CUMPLE	2025-07-07 19:21:00
1163	2891448	NO CUMPLE	2025-07-07 19:21:00
1164	4494823	NO CUMPLE	2025-07-07 19:21:00
1165	4446765	NO CUMPLE	2025-07-07 19:21:00
1166	4446766	NO CUMPLE	2025-07-07 19:21:00
1167	4019527	NO CUMPLE	2025-07-07 19:21:00
1168	1339014	NO CUMPLE	2025-07-07 19:21:00
1169	2981228	NO CUMPLE	2025-07-07 19:21:00
1170	2706525	NO CUMPLE	2025-07-07 19:21:00
1171	2706527	NO CUMPLE	2025-07-07 19:21:00
1172	2394157	NO CUMPLE	2025-07-07 19:21:00
1173	2357071	NO CUMPLE	2025-07-07 19:21:00
1174	5514861	NO CUMPLE	2025-07-07 19:21:00
1175	5564144	NO CUMPLE	2025-07-07 19:21:00
1176	2962882	CUMPLE	2025-07-07 19:21:00
1177	4192769	NO CUMPLE	2025-07-07 19:21:00
1178	4484830	NO CUMPLE	2025-07-07 19:21:00
1179	4545902	NO CUMPLE	2025-07-07 19:21:00
1180	4016139	CUMPLE	2025-07-07 19:21:00
1181	4083904	NO CUMPLE	2025-07-07 19:21:00
1182	4484575	NO CUMPLE	2025-07-07 19:21:00
1183	4756883	NO CUMPLE	2025-07-07 19:21:00
1184	2881865	CUMPLE	2025-07-07 19:21:00
1185	2969254	NO CUMPLE	2025-07-07 19:21:00
1186	4899450	CUMPLE	2025-07-07 19:21:00
1187	2414533	CUMPLE	2025-07-07 19:21:00
1188	5399074	CUMPLE	2025-07-07 19:21:00
1189	5399073	CUMPLE	2025-07-07 19:21:00
1190	5399072	CUMPLE	2025-07-07 19:21:00
1191	5399071	CUMPLE	2025-07-07 19:21:00
1192	5399070	CUMPLE	2025-07-07 19:21:00
1193	5399068	CUMPLE	2025-07-07 19:21:00
1194	4287789	CUMPLE	2025-07-07 19:21:00
1195	2414532	CUMPLE	2025-07-07 19:21:00
1196	2414535	CUMPLE	2025-07-07 19:21:00
1197	2841164	CUMPLE	2025-07-07 19:21:00
1198	2989503	NO CUMPLE	2025-07-07 19:21:00
1199	5045539	NO CUMPLE	2025-07-07 19:21:00
1200	2578774	CUMPLE	2025-07-07 19:21:00
1201	4267807	CUMPLE	2025-07-07 19:21:00
1202	4747809	CUMPLE	2025-07-07 19:21:00
1203	4307604	NO CUMPLE	2025-07-07 19:21:00
1204	2696876	NO CUMPLE	2025-07-07 19:21:00
1205	2514853	NO CUMPLE	2025-07-07 19:21:00
1206	2617507	NO CUMPLE	2025-07-07 19:21:00
1207	4282916	NO CUMPLE	2025-07-07 19:21:00
1208	2732148	CUMPLE	2025-07-07 19:21:00
1209	4288160	NO CUMPLE	2025-07-07 19:21:00
1210	4288161	CUMPLE	2025-07-07 19:21:00
1211	4288163	NO CUMPLE	2025-07-07 19:21:00
1212	4465528	NO CUMPLE	2025-07-07 19:21:00
1213	4844351	CUMPLE	2025-07-07 19:21:00
1214	4844354	CUMPLE	2025-07-07 19:21:00
1215	4293966	NO CUMPLE	2025-07-07 19:21:00
1216	4469473	NO CUMPLE	2025-07-07 19:21:00
1217	2621309	NO CUMPLE	2025-07-07 19:21:00
1218	4569167	CUMPLE	2025-07-07 19:21:00
1219	4569168	CUMPLE	2025-07-07 19:21:00
1220	4757325	NO CUMPLE	2025-07-07 19:21:00
1221	5055380	CUMPLE	2025-07-07 19:21:00
1222	5055893	CUMPLE	2025-07-07 19:21:00
1223	5055895	CUMPLE	2025-07-07 19:21:00
1224	2888358	NO CUMPLE	2025-07-07 19:21:00
1225	2888363	NO CUMPLE	2025-07-07 19:21:00
1226	4454541	CUMPLE	2025-07-07 19:21:00
1227	4525728	NO CUMPLE	2025-07-07 19:21:00
1228	4569367	CUMPLE	2025-07-07 19:21:00
1229	4228804	NO CUMPLE	2025-07-07 19:21:00
1230	2747957	NO CUMPLE	2025-07-07 19:21:00
1231	4027243	CUMPLE	2025-07-07 19:21:00
1232	4308507	NO CUMPLE	2025-07-07 19:21:00
1233	4388376	NO CUMPLE	2025-07-07 19:21:00
1234	4899391	NO CUMPLE	2025-07-07 19:21:00
1235	4899392	NO CUMPLE	2025-07-07 19:21:00
1236	2380816	NO CUMPLE	2025-07-07 19:21:00
1237	2664589	NO CUMPLE	2025-07-07 19:21:00
1238	1314795	NO CUMPLE	2025-07-07 19:21:00
1239	699402	NO CUMPLE	2025-07-07 19:21:00
1240	2563161	NO CUMPLE	2025-07-07 19:21:00
1241	4016140	NO CUMPLE	2025-07-07 19:21:00
1242	4290359	NO CUMPLE	2025-07-07 19:21:00
1243	4033201	NO CUMPLE	2025-07-07 19:21:00
1244	2141853	CUMPLE	2025-07-07 19:21:00
1245	2141855	CUMPLE	2025-07-07 19:21:00
1246	4009641	CUMPLE	2025-07-07 19:21:00
1247	5450421	CUMPLE	2025-07-07 19:21:00
1248	5450425	CUMPLE	2025-07-07 19:21:00
1249	5154690	CUMPLE	2025-07-07 19:21:00
1250	5154694	CUMPLE	2025-07-07 19:21:00
1251	5154696	CUMPLE	2025-07-07 19:21:00
1252	4231204	NO CUMPLE	2025-07-07 19:21:00
1253	2981226	NO CUMPLE	2025-07-07 19:21:00
1254	4181596	NO CUMPLE	2025-07-07 19:21:00
1255	2987100	NO CUMPLE	2025-07-07 19:21:00
1256	4005190	NO CUMPLE	2025-07-07 19:21:00
1257	4986397	CUMPLE	2025-07-07 19:21:00
1258	4237440	CUMPLE	2025-07-07 19:21:00
1259	4899190	NO CUMPLE	2025-07-07 19:21:00
1260	2648468	NO CUMPLE	2025-07-07 19:21:00
1261	2974116	NO CUMPLE	2025-07-07 19:21:00
1262	4084522	CUMPLE	2025-07-07 19:21:00
1263	2765856	NO CUMPLE	2025-07-07 19:21:00
1264	5154700	CUMPLE	2025-07-07 19:21:00
1265	5154701	CUMPLE	2025-07-07 19:21:00
1266	5278803	NO CUMPLE	2025-07-07 19:21:00
1267	2925617	NO CUMPLE	2025-07-07 19:21:00
1268	5367307	NO CUMPLE	2025-07-07 19:21:00
1269	2894645	CUMPLE	2025-07-07 19:21:00
1270	5008569	NO CUMPLE	2025-07-07 19:21:00
1271	5008904	NO CUMPLE	2025-07-07 19:21:00
1272	4486494	NO CUMPLE	2025-07-07 19:21:00
1273	4767627	NO CUMPLE	2025-07-07 19:21:00
1274	4767716	NO CUMPLE	2025-07-07 19:21:00
1275	4361605	NO CUMPLE	2025-07-07 19:21:00
1276	4531443	NO CUMPLE	2025-07-07 19:21:00
1277	2715242	CUMPLE	2025-07-07 19:21:00
1278	5004755	NO CUMPLE	2025-07-07 19:21:00
1279	4997217	NO CUMPLE	2025-07-07 19:21:00
1280	2228958	NO CUMPLE	2025-07-07 19:21:00
1281	4480161	NO CUMPLE	2025-07-07 19:21:00
1282	4105384	NO CUMPLE	2025-07-07 19:21:00
1283	5056499	NO CUMPLE	2025-07-07 19:21:00
1284	4786659	CUMPLE	2025-07-07 19:21:00
1285	4375765	NO CUMPLE	2025-07-07 19:21:00
1286	2695424	CUMPLE	2025-07-07 19:21:00
1287	5225397	CUMPLE	2025-07-07 19:21:00
1288	5225398	CUMPLE	2025-07-07 19:21:00
1289	4349757	NO CUMPLE	2025-07-07 19:21:00
1290	4773296	CUMPLE	2025-07-07 19:21:00
1291	5415302	CUMPLE	2025-07-07 19:21:00
1292	4234170	NO CUMPLE	2025-07-07 19:21:00
1293	4237781	NO CUMPLE	2025-07-07 19:21:00
1294	4767715	CUMPLE	2025-07-07 19:21:00
1295	2959115	NO CUMPLE	2025-07-07 19:21:00
1296	4402568	NO CUMPLE	2025-07-07 19:21:00
1297	4402576	NO CUMPLE	2025-07-07 19:21:00
1298	2555308	NO CUMPLE	2025-07-07 19:21:00
1299	4729905	NO CUMPLE	2025-07-07 19:21:00
1300	4374806	NO CUMPLE	2025-07-07 19:21:00
1301	4966827	CUMPLE	2025-07-07 19:21:00
1302	4966828	CUMPLE	2025-07-07 19:21:00
1303	4966871	CUMPLE	2025-07-07 19:21:00
1304	4966874	CUMPLE	2025-07-07 19:21:00
1305	5056934	NO CUMPLE	2025-07-07 19:21:00
1306	5325128	CUMPLE	2025-07-07 19:21:00
1307	5528649	CUMPLE	2025-07-07 19:21:00
1308	5528651	CUMPLE	2025-07-07 19:21:00
1309	4178893	NO CUMPLE	2025-07-07 19:21:00
1310	4175636	CUMPLE	2025-07-07 19:21:00
1311	2897450	NO CUMPLE	2025-07-07 19:21:00
1312	2910280	NO CUMPLE	2025-07-07 19:21:00
1313	4288162	NO CUMPLE	2025-07-07 19:21:00
1314	4361430	NO CUMPLE	2025-07-07 19:21:00
1315	2464441	NO CUMPLE	2025-07-07 19:21:00
1316	2989400	NO CUMPLE	2025-07-07 19:21:00
1317	4690995	CUMPLE	2025-07-07 19:21:00
1318	4909570	CUMPLE	2025-07-07 19:21:00
1319	5411340	NO CUMPLE	2025-07-07 19:21:00
1320	5187245	CUMPLE	2025-07-07 19:21:00
1321	5411281	CUMPLE	2025-07-07 19:21:00
1322	5411282	CUMPLE	2025-07-07 19:21:00
1323	5411283	CUMPLE	2025-07-07 19:21:00
1324	4542620	NO CUMPLE	2025-07-07 19:21:00
1325	4882784	NO CUMPLE	2025-07-07 19:21:00
1326	5416014	CUMPLE	2025-07-07 19:21:00
1327	4767711	NO CUMPLE	2025-07-07 19:21:00
1328	5415232	CUMPLE	2025-07-07 19:21:00
1329	5415233	CUMPLE	2025-07-07 19:21:00
1330	2733598	NO CUMPLE	2025-07-07 19:21:00
1331	2891445	NO CUMPLE	2025-07-07 19:21:00
1332	5024979	CUMPLE	2025-07-07 19:21:00
1333	2965199	CUMPLE	2025-07-07 19:21:00
1334	4348308	CUMPLE	2025-07-07 19:21:00
1335	4467406	NO CUMPLE	2025-07-07 19:21:00
1336	4757559	NO CUMPLE	2025-07-07 19:21:00
1337	5084557	NO CUMPLE	2025-07-07 19:21:00
1338	5084560	NO CUMPLE	2025-07-07 19:21:00
1339	1840230	CUMPLE	2025-07-07 19:21:00
1340	2712372	CUMPLE	2025-07-07 19:21:00
1341	2726078	CUMPLE	2025-07-07 19:21:00
1342	4448196	NO CUMPLE	2025-07-07 19:21:00
1343	5436286	NO CUMPLE	2025-07-07 19:21:00
1344	4807076	NO CUMPLE	2025-07-07 19:21:00
1345	5038097	NO CUMPLE	2025-07-07 19:21:00
1346	4017485	CUMPLE	2025-07-07 19:21:00
1347	4025153	NO CUMPLE	2025-07-07 19:21:00
1348	4825458	NO CUMPLE	2025-07-07 19:21:00
1349	5057633	CUMPLE	2025-07-07 19:21:00
1350	5395773	CUMPLE	2025-07-07 19:21:00
1351	5417975	CUMPLE	2025-07-07 19:21:00
1352	2696875	NO CUMPLE	2025-07-07 19:21:00
1353	2454975	NO CUMPLE	2025-07-07 19:21:00
1354	4004121	NO CUMPLE	2025-07-07 19:21:00
1355	2883039	NO CUMPLE	2025-07-07 19:21:00
1356	2910278	NO CUMPLE	2025-07-07 19:21:00
1357	4166580	CUMPLE	2025-07-07 19:21:00
1358	4468906	NO CUMPLE	2025-07-07 19:21:00
1359	4468925	CUMPLE	2025-07-07 19:21:00
1360	4468926	CUMPLE	2025-07-07 19:21:00
1361	4480789	CUMPLE	2025-07-07 19:21:00
1362	4037351	NO CUMPLE	2025-07-07 19:21:00
1363	4375790	NO CUMPLE	2025-07-07 19:21:00
1364	2714805	CUMPLE	2025-07-07 19:21:00
1365	4227423	CUMPLE	2025-07-07 19:21:00
1366	2652725	NO CUMPLE	2025-07-07 19:21:00
1367	4878777	NO CUMPLE	2025-07-07 19:21:00
1368	5225391	CUMPLE	2025-07-07 19:21:00
1369	5225393	NO CUMPLE	2025-07-07 19:21:00
1370	4846273	CUMPLE	2025-07-07 19:21:00
1371	4846276	CUMPLE	2025-07-07 19:21:00
1372	4545840	NO CUMPLE	2025-07-07 19:21:00
1373	4545842	NO CUMPLE	2025-07-07 19:21:00
1374	5057381	NO CUMPLE	2025-07-07 19:21:00
1375	4027244	CUMPLE	2025-07-07 19:21:00
1376	4542622	CUMPLE	2025-07-07 19:21:00
1377	4833373	NO CUMPLE	2025-07-07 19:21:00
1378	4833374	NO CUMPLE	2025-07-07 19:21:00
1379	4833375	NO CUMPLE	2025-07-07 19:21:00
1380	4976457	NO CUMPLE	2025-07-07 19:21:00
1381	4596314	NO CUMPLE	2025-07-07 19:21:00
1382	2934616	NO CUMPLE	2025-07-07 19:21:00
1383	2934617	NO CUMPLE	2025-07-07 19:21:00
1384	2934618	NO CUMPLE	2025-07-07 19:21:00
1385	2934619	NO CUMPLE	2025-07-07 19:21:00
1386	2883531	CUMPLE	2025-07-07 19:21:00
1387	2883532	CUMPLE	2025-07-07 19:21:00
1388	2577133	NO CUMPLE	2025-07-07 19:21:00
1389	2726080	CUMPLE	2025-07-07 19:21:00
1390	4747581	NO CUMPLE	2025-07-07 19:21:00
1391	5205572	CUMPLE	2025-07-07 19:21:00
1392	5393077	CUMPLE	2025-07-07 19:21:00
1393	5393079	CUMPLE	2025-07-07 19:21:00
1394	5274716	NO CUMPLE	2025-07-07 19:21:00
1395	5274717	NO CUMPLE	2025-07-07 19:21:00
1396	5153981	CUMPLE	2025-07-07 19:21:00
1397	5153986	CUMPLE	2025-07-07 19:21:00
1398	4735701	NO CUMPLE	2025-07-07 19:21:00
1399	5397172	NO CUMPLE	2025-07-07 19:21:00
1400	4855723	CUMPLE	2025-07-07 19:21:00
1401	5516931	NO CUMPLE	2025-07-07 19:21:00
1402	2617528	NO CUMPLE	2025-07-07 19:21:00
1403	4375763	CUMPLE	2025-07-07 19:21:00
1404	4189643	CUMPLE	2025-07-07 19:21:00
1405	4189647	NO CUMPLE	2025-07-07 19:21:00
1406	4977240	NO CUMPLE	2025-07-07 19:21:00
1407	5004538	NO CUMPLE	2025-07-07 19:21:00
1408	5055362	CUMPLE	2025-07-07 19:21:00
1409	5284370	CUMPLE	2025-07-07 19:21:00
1410	5284378	CUMPLE	2025-07-07 19:21:00
1411	4924811	NO CUMPLE	2025-07-07 19:21:00
1412	5216786	CUMPLE	2025-07-07 19:21:00
1413	4797387	CUMPLE	2025-07-07 19:21:00
1414	4235484	NO CUMPLE	2025-07-07 19:21:00
1415	4235487	NO CUMPLE	2025-07-07 19:21:00
1416	4801852	CUMPLE	2025-07-07 19:21:00
1417	2475300	NO CUMPLE	2025-07-07 19:21:00
1418	2920411	NO CUMPLE	2025-07-07 19:21:00
1419	2920413	NO CUMPLE	2025-07-07 19:21:00
1420	4083910	NO CUMPLE	2025-07-07 19:21:00
1421	4033288	NO CUMPLE	2025-07-07 19:21:00
1422	4651996	NO CUMPLE	2025-07-07 19:21:00
1423	5187814	NO CUMPLE	2025-07-07 19:21:00
1424	5426110	CUMPLE	2025-07-07 19:21:00
1425	5426111	CUMPLE	2025-07-07 19:21:00
1426	5426113	CUMPLE	2025-07-07 19:21:00
1427	4339475	NO CUMPLE	2025-07-07 19:21:00
1428	4339476	NO CUMPLE	2025-07-07 19:21:00
1429	4339477	NO CUMPLE	2025-07-07 19:21:00
1430	4806651	CUMPLE	2025-07-07 19:21:00
1431	4806652	NO CUMPLE	2025-07-07 19:21:00
1432	4806653	NO CUMPLE	2025-07-07 19:21:00
1433	4998469	NO CUMPLE	2025-07-07 19:21:00
1434	4998468	NO CUMPLE	2025-07-07 19:21:00
1435	4998467	NO CUMPLE	2025-07-07 19:21:00
1436	4998466	NO CUMPLE	2025-07-07 19:21:00
1437	4998465	NO CUMPLE	2025-07-07 19:21:00
1438	4549003	NO CUMPLE	2025-07-07 19:21:00
1439	4105352	NO CUMPLE	2025-07-07 19:21:00
1440	4374805	NO CUMPLE	2025-07-07 19:21:00
1441	5056938	NO CUMPLE	2025-07-07 19:21:00
1442	5153982	CUMPLE	2025-07-07 19:21:00
1443	5153983	CUMPLE	2025-07-07 19:21:00
1444	5393607	CUMPLE	2025-07-07 19:21:00
1445	5448207	CUMPLE	2025-07-07 19:21:00
1446	2708562	NO CUMPLE	2025-07-07 19:21:00
1447	2578976	CUMPLE	2025-07-07 19:21:00
1448	2984895	CUMPLE	2025-07-07 19:21:00
1449	4197076	NO CUMPLE	2025-07-07 19:21:00
1450	4309444	NO CUMPLE	2025-07-07 19:21:00
1451	4309446	NO CUMPLE	2025-07-07 19:21:00
1452	4789035	NO CUMPLE	2025-07-07 19:21:00
1453	4975521	CUMPLE	2025-07-07 19:21:00
1454	2989398	NO CUMPLE	2025-07-07 19:21:00
1455	4333508	NO CUMPLE	2025-07-07 19:21:00
1456	4577260	NO CUMPLE	2025-07-07 19:21:00
1457	4744698	NO CUMPLE	2025-07-07 19:21:00
1458	5104632	NO CUMPLE	2025-07-07 19:21:00
1459	4846274	CUMPLE	2025-07-07 19:21:00
1460	4031950	NO CUMPLE	2025-07-07 19:21:00
1461	5056988	NO CUMPLE	2025-07-07 19:21:00
1462	5065122	NO CUMPLE	2025-07-07 19:21:00
1463	5205878	CUMPLE	2025-07-07 19:21:00
1464	5417487	CUMPLE	2025-07-07 19:21:00
1465	2940689	CUMPLE	2025-07-07 19:21:00
1466	4011249	NO CUMPLE	2025-07-07 19:21:00
1467	4011250	NO CUMPLE	2025-07-07 19:21:00
1468	4011251	CUMPLE	2025-07-07 19:21:00
1469	2885363	CUMPLE	2025-07-07 19:21:00
1470	2556249	NO CUMPLE	2025-07-07 19:21:00
1471	2556251	NO CUMPLE	2025-07-07 19:21:00
1472	2556252	NO CUMPLE	2025-07-07 19:21:00
1473	2754695	NO CUMPLE	2025-07-07 19:21:00
1474	2754696	NO CUMPLE	2025-07-07 19:21:00
1475	5294507	CUMPLE	2025-07-07 19:21:00
1476	4018933	NO CUMPLE	2025-07-07 19:21:00
1477	2899311	CUMPLE	2025-07-07 19:21:00
1478	4006205	CUMPLE	2025-07-07 19:21:00
1479	4837360	CUMPLE	2025-07-07 19:21:00
1480	2984893	CUMPLE	2025-07-07 19:21:00
1481	2984894	NO CUMPLE	2025-07-07 19:21:00
1482	4166579	NO CUMPLE	2025-07-07 19:21:00
1483	4925497	NO CUMPLE	2025-07-07 19:21:00
1484	4844352	CUMPLE	2025-07-07 19:21:00
1485	4925256	NO CUMPLE	2025-07-07 19:21:00
1486	2747955	NO CUMPLE	2025-07-07 19:21:00
1487	4438963	NO CUMPLE	2025-07-07 19:21:00
1488	4194320	NO CUMPLE	2025-07-07 19:21:00
1489	4032265	NO CUMPLE	2025-07-07 19:21:00
1490	5189942	CUMPLE	2025-07-07 19:21:00
1491	5189946	CUMPLE	2025-07-07 19:21:00
1492	5189950	CUMPLE	2025-07-07 19:21:00
1493	5448559	CUMPLE	2025-07-07 19:21:00
1494	5448561	CUMPLE	2025-07-07 19:21:00
1495	5448562	CUMPLE	2025-07-07 19:21:00
1496	2954994	NO CUMPLE	2025-07-07 19:21:00
1497	5414222	CUMPLE	2025-07-07 19:21:00
1498	5414226	CUMPLE	2025-07-07 19:21:00
1499	5042467	CUMPLE	2025-07-07 19:21:00
1500	4050054	NO CUMPLE	2025-07-07 19:21:00
1501	5057090	NO CUMPLE	2025-07-07 19:21:00
1502	2715556	CUMPLE	2025-07-07 19:21:00
1503	2715558	CUMPLE	2025-07-07 19:21:00
1504	2176144	CUMPLE	2025-07-07 19:21:00
1505	2730438	CUMPLE	2025-07-07 19:21:00
1506	2730437	CUMPLE	2025-07-07 19:21:00
1507	2730436	CUMPLE	2025-07-07 19:21:00
1508	2730435	CUMPLE	2025-07-07 19:21:00
1509	4569197	CUMPLE	2025-07-07 19:21:00
1510	4569196	CUMPLE	2025-07-07 19:21:00
1511	4569195	CUMPLE	2025-07-07 19:21:00
1512	4560176	NO CUMPLE	2025-07-07 19:21:00
1513	5354086	CUMPLE	2025-07-07 19:21:00
1514	5354085	CUMPLE	2025-07-07 19:21:00
1515	5354084	CUMPLE	2025-07-07 19:21:00
1516	5354083	CUMPLE	2025-07-07 19:21:00
1517	5354082	CUMPLE	2025-07-07 19:21:00
1518	5354081	CUMPLE	2025-07-07 19:21:00
1519	5206104	CUMPLE	2025-07-07 19:21:00
1520	5206103	CUMPLE	2025-07-07 19:21:00
1521	5206102	CUMPLE	2025-07-07 19:21:00
1522	5206101	CUMPLE	2025-07-07 19:21:00
1523	5206100	CUMPLE	2025-07-07 19:21:00
1524	5103767	CUMPLE	2025-07-07 19:21:00
1525	5103766	CUMPLE	2025-07-07 19:21:00
1526	5103765	CUMPLE	2025-07-07 19:21:00
1527	5103764	CUMPLE	2025-07-07 19:21:00
1528	5103763	CUMPLE	2025-07-07 19:21:00
1529	5448068	CUMPLE	2025-07-07 19:21:00
1530	4569198	CUMPLE	2025-07-07 19:21:00
1531	4569194	CUMPLE	2025-07-07 19:21:00
1532	4481274	CUMPLE	2025-07-07 19:21:00
1533	4481275	CUMPLE	2025-07-07 19:21:00
1534	4481276	CUMPLE	2025-07-07 19:21:00
1535	4548081	CUMPLE	2025-07-07 19:21:00
1536	4548082	CUMPLE	2025-07-07 19:21:00
1537	4548083	CUMPLE	2025-07-07 19:21:00
1538	4854119	CUMPLE	2025-07-07 19:21:00
1539	4967626	CUMPLE	2025-07-07 19:21:00
1540	4967634	CUMPLE	2025-07-07 19:21:00
1541	5164726	CUMPLE	2025-07-07 19:21:00
1542	5164732	CUMPLE	2025-07-07 19:21:00
1543	5351853	CUMPLE	2025-07-07 19:21:00
1544	5351854	CUMPLE	2025-07-07 19:21:00
1545	5351856	CUMPLE	2025-07-07 19:21:00
1546	5356594	CUMPLE	2025-07-07 19:21:00
1547	5400060	CUMPLE	2025-07-07 19:21:00
1548	5486137	CUMPLE	2025-07-07 19:21:00
1549	5545890	CUMPLE	2025-07-07 19:21:00
1550	5551068	CUMPLE	2025-07-07 19:21:00
1551	5367299	CUMPLE	2025-07-07 19:21:00
1552	4714380	CUMPLE	2025-07-07 19:21:00
1553	2696894	CUMPLE	2025-07-07 19:21:00
1554	2458969	CUMPLE	2025-07-07 19:21:00
1555	4513998	CUMPLE	2025-07-07 19:21:00
1556	4898242	CUMPLE	2025-07-07 19:21:00
1557	4898243	CUMPLE	2025-07-07 19:21:00
1558	2735541	CUMPLE	2025-07-07 19:21:00
1559	4478723	CUMPLE	2025-07-07 19:21:00
1560	4713643	CUMPLE	2025-07-07 19:21:00
1561	4736061	CUMPLE	2025-07-07 19:21:00
1562	4977238	NO CUMPLE	2025-07-07 19:21:00
1563	5055368	CUMPLE	2025-07-07 19:21:00
1564	5273840	CUMPLE	2025-07-07 19:21:00
1565	5273844	CUMPLE	2025-07-07 19:21:00
1566	5273845	CUMPLE	2025-07-07 19:21:00
1567	5319250	CUMPLE	2025-07-07 19:21:00
1568	5319252	CUMPLE	2025-07-07 19:21:00
1569	5334152	CUMPLE	2025-07-07 19:21:00
1570	5334153	CUMPLE	2025-07-07 19:21:00
1571	5334154	CUMPLE	2025-07-07 19:21:00
1572	5334155	CUMPLE	2025-07-07 19:21:00
1573	5334156	CUMPLE	2025-07-07 19:21:00
1574	5335438	CUMPLE	2025-07-07 19:21:00
1575	5335439	CUMPLE	2025-07-07 19:21:00
1576	5335440	CUMPLE	2025-07-07 19:21:00
1577	5335441	CUMPLE	2025-07-07 19:21:00
1578	5335442	CUMPLE	2025-07-07 19:21:00
1579	5335443	CUMPLE	2025-07-07 19:21:00
1580	4322059	CUMPLE	2025-07-07 19:21:00
1581	2921593	CUMPLE	2025-07-07 19:21:00
1582	4973801	CUMPLE	2025-07-07 19:21:00
1583	4973802	CUMPLE	2025-07-07 19:21:00
1584	4973803	CUMPLE	2025-07-07 19:21:00
1585	4973805	CUMPLE	2025-07-07 19:21:00
1586	4973806	CUMPLE	2025-07-07 19:21:00
1587	5256262	CUMPLE	2025-07-07 19:21:00
1588	5450795	CUMPLE	2025-07-07 19:21:00
1589	5332861	NO CUMPLE	2025-07-07 19:21:00
1590	5332863	NO CUMPLE	2025-07-07 19:21:00
1591	5395643	NO CUMPLE	2025-07-07 19:21:00
1592	5395645	NO CUMPLE	2025-07-07 19:21:00
1593	5425046	CUMPLE	2025-07-07 19:21:00
1594	4229062	CUMPLE	2025-07-07 19:21:00
1595	4194319	CUMPLE	2025-07-07 19:21:00
1596	4083850	CUMPLE	2025-07-07 19:21:00
1597	4083852	CUMPLE	2025-07-07 19:21:00
1598	2657112	NO CUMPLE	2025-07-07 19:21:00
1599	4010643	CUMPLE	2025-07-07 19:21:00
1600	2754921	NO CUMPLE	2025-07-07 19:21:00
1601	2754922	NO CUMPLE	2025-07-07 19:21:00
1602	2754926	NO CUMPLE	2025-07-07 19:21:00
1603	4566690	CUMPLE	2025-07-07 19:21:00
1604	4156017	CUMPLE	2025-07-07 19:21:00
1605	4591868	CUMPLE	2025-07-07 19:21:00
1606	4774031	CUMPLE	2025-07-07 19:21:00
1607	5101431	CUMPLE	2025-07-07 19:21:00
1608	5186164	CUMPLE	2025-07-07 19:21:00
1609	5186166	CUMPLE	2025-07-07 19:21:00
1610	4480971	CUMPLE	2025-07-07 19:21:00
1611	4480972	CUMPLE	2025-07-07 19:21:00
1612	4480973	CUMPLE	2025-07-07 19:21:00
1613	4480974	CUMPLE	2025-07-07 19:21:00
1614	2722893	CUMPLE	2025-07-07 19:21:00
1615	5042466	CUMPLE	2025-07-07 19:21:00
1616	5042469	CUMPLE	2025-07-07 19:21:00
1617	4744607	CUMPLE	2025-07-07 19:21:00
1618	4313851	CUMPLE	2025-07-07 19:21:00
1619	4327055	CUMPLE	2025-07-07 19:21:00
1620	4996805	NO CUMPLE	2025-07-07 19:21:00
1621	4996806	NO CUMPLE	2025-07-07 19:21:00
1622	4996809	NO CUMPLE	2025-07-07 19:21:00
1623	5404858	NO CUMPLE	2025-07-07 19:21:00
1624	2453782	NO CUMPLE	2025-07-07 19:21:00
1625	4479403	CUMPLE	2025-07-07 19:21:00
1626	2696878	NO CUMPLE	2025-07-07 19:21:00
1627	5407152	CUMPLE	2025-07-07 19:21:00
1628	2707979	CUMPLE	2025-07-07 19:21:00
1629	2877795	NO CUMPLE	2025-07-07 19:21:00
1630	4323709	CUMPLE	2025-07-07 19:21:00
1631	4894512	CUMPLE	2025-07-07 19:21:00
1632	4894514	CUMPLE	2025-07-07 19:21:00
1633	4894515	CUMPLE	2025-07-07 19:21:00
1634	4894516	CUMPLE	2025-07-07 19:21:00
1635	2562322	NO CUMPLE	2025-07-07 19:21:00
1636	4010956	NO CUMPLE	2025-07-07 19:21:00
1637	4127876	CUMPLE	2025-07-07 19:21:00
1638	4127878	CUMPLE	2025-07-07 19:21:00
1639	4190006	NO CUMPLE	2025-07-07 19:21:00
1640	4569169	CUMPLE	2025-07-07 19:21:00
1641	4690991	CUMPLE	2025-07-07 19:21:00
1642	4814032	CUMPLE	2025-07-07 19:21:00
1643	4814033	CUMPLE	2025-07-07 19:21:00
1644	5044687	NO CUMPLE	2025-07-07 19:21:00
1645	5044688	NO CUMPLE	2025-07-07 19:21:00
1646	5104620	NO CUMPLE	2025-07-07 19:21:00
1647	5104622	NO CUMPLE	2025-07-07 19:21:00
1648	5104633	NO CUMPLE	2025-07-07 19:21:00
1649	5225390	CUMPLE	2025-07-07 19:21:00
1650	5225392	CUMPLE	2025-07-07 19:21:00
1651	5225395	CUMPLE	2025-07-07 19:21:00
1652	5273850	NO CUMPLE	2025-07-07 19:21:00
1653	4481273	CUMPLE	2025-07-07 19:21:00
1654	4560121	CUMPLE	2025-07-07 19:21:00
1655	4846290	CUMPLE	2025-07-07 19:21:00
1656	4846291	CUMPLE	2025-07-07 19:21:00
1657	4846292	CUMPLE	2025-07-07 19:21:00
1658	4846293	CUMPLE	2025-07-07 19:21:00
1659	4846295	CUMPLE	2025-07-07 19:21:00
1660	4944332	NO CUMPLE	2025-07-07 19:21:00
1661	4967635	CUMPLE	2025-07-07 19:21:00
1662	5158227	NO CUMPLE	2025-07-07 19:21:00
1663	5158231	NO CUMPLE	2025-07-07 19:21:00
1664	5400061	CUMPLE	2025-07-07 19:21:00
1665	5400062	CUMPLE	2025-07-07 19:21:00
1666	5411304	NO CUMPLE	2025-07-07 19:21:00
1667	5411305	NO CUMPLE	2025-07-07 19:21:00
1668	5416929	NO CUMPLE	2025-07-07 19:21:00
1669	5416930	NO CUMPLE	2025-07-07 19:21:00
1670	5416931	NO CUMPLE	2025-07-07 19:21:00
1671	5416932	NO CUMPLE	2025-07-07 19:21:00
1672	5416933	NO CUMPLE	2025-07-07 19:21:00
1673	2654202	NO CUMPLE	2025-07-07 19:21:00
1674	4027246	NO CUMPLE	2025-07-07 19:21:00
1675	4523620	NO CUMPLE	2025-07-07 19:21:00
1676	4531962	NO CUMPLE	2025-07-07 19:21:00
1677	4531963	NO CUMPLE	2025-07-07 19:21:00
1678	4540089	NO CUMPLE	2025-07-07 19:21:00
1679	4540091	NO CUMPLE	2025-07-07 19:21:00
1680	4540092	NO CUMPLE	2025-07-07 19:21:00
1681	4540093	NO CUMPLE	2025-07-07 19:21:00
1682	4878639	NO CUMPLE	2025-07-07 19:21:00
1683	4878641	NO CUMPLE	2025-07-07 19:21:00
1684	5417689	CUMPLE	2025-07-07 19:21:00
1685	4493643	NO CUMPLE	2025-07-07 19:21:00
1686	4493644	NO CUMPLE	2025-07-07 19:21:00
1687	4565005	NO CUMPLE	2025-07-07 19:21:00
1688	4866350	NO CUMPLE	2025-07-07 19:21:00
1689	4898480	NO CUMPLE	2025-07-07 19:21:00
1690	4898523	NO CUMPLE	2025-07-07 19:21:00
1691	2975251	NO CUMPLE	2025-07-07 19:21:00
1692	4438965	NO CUMPLE	2025-07-07 19:21:00
1693	1314778	NO CUMPLE	2025-07-07 19:21:00
1694	4528170	NO CUMPLE	2025-07-07 19:21:00
1695	4596313	CUMPLE	2025-07-07 19:21:00
1696	4050396	CUMPLE	2025-07-07 19:21:00
1697	4050399	CUMPLE	2025-07-07 19:21:00
1698	4050400	CUMPLE	2025-07-07 19:21:00
1699	4050401	CUMPLE	2025-07-07 19:21:00
1700	4050402	CUMPLE	2025-07-07 19:21:00
1701	4050403	CUMPLE	2025-07-07 19:21:00
1702	5045363	NO CUMPLE	2025-07-07 19:21:00
1703	5145112	CUMPLE	2025-07-07 19:21:00
1704	4182747	NO CUMPLE	2025-07-07 19:21:00
1705	4467344	NO CUMPLE	2025-07-07 19:21:00
1706	4467346	NO CUMPLE	2025-07-07 19:21:00
1707	5405204	CUMPLE	2025-07-07 19:21:00
1708	5405210	CUMPLE	2025-07-07 19:21:00
1709	5447836	NO CUMPLE	2025-07-07 19:21:00
1710	5447837	NO CUMPLE	2025-07-07 19:21:00
1711	5448564	NO CUMPLE	2025-07-07 19:21:00
1712	5449685	NO CUMPLE	2025-07-07 19:21:00
1713	5449695	NO CUMPLE	2025-07-07 19:21:00
1714	5449713	NO CUMPLE	2025-07-07 19:21:00
1715	5449715	NO CUMPLE	2025-07-07 19:21:00
1716	5450094	NO CUMPLE	2025-07-07 19:21:00
1717	5450096	NO CUMPLE	2025-07-07 19:21:00
1718	5450098	NO CUMPLE	2025-07-07 19:21:00
1719	5467148	CUMPLE	2025-07-07 19:21:00
1720	5467150	CUMPLE	2025-07-07 19:21:00
1721	5467152	CUMPLE	2025-07-07 19:21:00
1722	5039773	NO CUMPLE	2025-07-07 19:21:00
1723	2754924	NO CUMPLE	2025-07-07 19:21:00
1724	2577135	NO CUMPLE	2025-07-07 19:21:00
1725	4776664	CUMPLE	2025-07-07 19:21:00
1726	4844152	NO CUMPLE	2025-07-07 19:21:00
1727	5397801	CUMPLE	2025-07-07 19:21:00
1728	5543250	CUMPLE	2025-07-07 19:21:00
1729	2555320	NO CUMPLE	2025-07-07 19:21:00
1730	4001660	NO CUMPLE	2025-07-07 19:21:00
1731	4407095	NO CUMPLE	2025-07-07 19:21:00
1732	4950668	NO CUMPLE	2025-07-07 19:21:00
1733	4351396	NO CUMPLE	2025-07-07 19:21:00
1734	4351398	NO CUMPLE	2025-07-07 19:21:00
1735	4351399	NO CUMPLE	2025-07-07 19:21:00
1736	4351400	NO CUMPLE	2025-07-07 19:21:00
1737	2758192	CUMPLE	2025-07-07 19:21:00
1738	4451179	NO CUMPLE	2025-07-07 19:21:00
1739	4454099	NO CUMPLE	2025-07-07 19:21:00
1740	5447379	NO CUMPLE	2025-07-07 19:21:00
1741	2963040	NO CUMPLE	2025-07-07 19:21:00
1742	5185486	CUMPLE	2025-07-07 19:21:00
1743	5448210	CUMPLE	2025-07-07 19:21:00
1744	5532240	CUMPLE	2025-07-07 19:21:00
1745	5532241	CUMPLE	2025-07-07 19:21:00
1746	5532244	CUMPLE	2025-07-07 19:21:00
1747	5134386	CUMPLE	2025-07-07 19:21:00
1748	5134389	CUMPLE	2025-07-07 19:21:00
1749	2919138	CUMPLE	2025-07-07 19:21:00
1750	2919140	CUMPLE	2025-07-07 19:21:00
1751	4569170	CUMPLE	2025-07-07 19:21:00
1752	5044636	CUMPLE	2025-07-07 19:21:00
1753	5044637	CUMPLE	2025-07-07 19:21:00
1754	5044638	CUMPLE	2025-07-07 19:21:00
1755	5044639	CUMPLE	2025-07-07 19:21:00
1756	5044640	CUMPLE	2025-07-07 19:21:00
1757	4788535	CUMPLE	2025-07-07 19:21:00
1758	2669068	CUMPLE	2025-07-07 19:21:00
1759	2669069	CUMPLE	2025-07-07 19:21:00
1760	4002453	CUMPLE	2025-07-07 19:21:00
1761	4439711	CUMPLE	2025-07-07 19:21:00
1762	4439716	CUMPLE	2025-07-07 19:21:00
1763	2029642	CUMPLE	2025-07-07 19:21:00
1764	4032211	CUMPLE	2025-07-07 19:21:00
1765	2652351	CUMPLE	2025-07-07 19:21:00
1766	5043600	CUMPLE	2025-07-07 19:21:00
1767	5189937	CUMPLE	2025-07-07 19:21:00
1768	5189948	CUMPLE	2025-07-07 19:21:00
1769	5448560	CUMPLE	2025-07-07 19:21:00
1770	5039774	CUMPLE	2025-07-07 19:21:00
1771	5039775	CUMPLE	2025-07-07 19:21:00
1772	5039776	CUMPLE	2025-07-07 19:21:00
1773	5278819	CUMPLE	2025-07-07 19:21:00
1774	5278820	CUMPLE	2025-07-07 19:21:00
1775	5278823	CUMPLE	2025-07-07 19:21:00
1776	5278824	CUMPLE	2025-07-07 19:21:00
1777	4170012	CUMPLE	2025-07-07 19:21:00
1778	4170020	CUMPLE	2025-07-07 19:21:00
1779	4484581	CUMPLE	2025-07-07 19:21:00
1780	4701936	CUMPLE	2025-07-07 19:21:00
1781	4747457	CUMPLE	2025-07-07 19:21:00
1782	4747459	CUMPLE	2025-07-07 19:21:00
1783	4747462	CUMPLE	2025-07-07 19:21:00
1784	4747468	CUMPLE	2025-07-07 19:21:00
1785	5393078	CUMPLE	2025-07-07 19:21:00
1786	5414223	CUMPLE	2025-07-07 19:21:00
1787	5414224	CUMPLE	2025-07-07 19:21:00
1788	5414225	CUMPLE	2025-07-07 19:21:00
1789	5450429	CUMPLE	2025-07-07 19:21:00
1790	5450431	CUMPLE	2025-07-07 19:21:00
1791	2555318	CUMPLE	2025-07-07 19:21:00
1792	5042470	CUMPLE	2025-07-07 19:21:00
1793	5450315	CUMPLE	2025-07-07 19:21:00
1794	5450316	CUMPLE	2025-07-07 19:21:00
1795	2715571	CUMPLE	2025-07-07 19:21:00
1796	5153984	CUMPLE	2025-07-07 19:21:00
1797	5153985	CUMPLE	2025-07-07 19:21:00
1798	4561952	CUMPLE	2025-07-07 19:21:00
1799	5405340	CUMPLE	2025-07-07 19:21:00
1800	4984204	CUMPLE	2025-07-07 19:21:00
1801	2189142	CUMPLE	2025-07-07 19:21:00
1802	4275492	CUMPLE	2025-07-07 19:21:00
1803	5407150	CUMPLE	2025-07-07 19:21:00
1804	5418029	CUMPLE	2025-07-07 19:21:00
1805	5418040	CUMPLE	2025-07-07 19:21:00
1806	4870149	CUMPLE	2025-07-07 19:21:00
1807	4870150	CUMPLE	2025-07-07 19:21:00
1808	4844350	CUMPLE	2025-07-07 19:21:00
1809	4127872	CUMPLE	2025-07-07 19:21:00
1810	4189646	CUMPLE	2025-07-07 19:21:00
1811	5185625	CUMPLE	2025-07-07 19:21:00
1812	5185628	CUMPLE	2025-07-07 19:21:00
1813	4454536	CUMPLE	2025-07-07 19:21:00
1814	5224740	CUMPLE	2025-07-07 19:21:00
1815	5224741	CUMPLE	2025-07-07 19:21:00
1816	5224742	CUMPLE	2025-07-07 19:21:00
1817	5224743	CUMPLE	2025-07-07 19:21:00
1818	5224744	CUMPLE	2025-07-07 19:21:00
1819	5411306	CUMPLE	2025-07-07 19:21:00
1820	5426917	CUMPLE	2025-07-07 19:21:00
1821	4320612	CUMPLE	2025-07-07 19:21:00
1822	4458013	CUMPLE	2025-07-07 19:21:00
1823	4540509	CUMPLE	2025-07-07 19:21:00
1824	5397215	CUMPLE	2025-07-07 19:21:00
1825	5397216	CUMPLE	2025-07-07 19:21:00
1826	5397217	CUMPLE	2025-07-07 19:21:00
1827	5397218	CUMPLE	2025-07-07 19:21:00
1828	5397219	CUMPLE	2025-07-07 19:21:00
1829	5397220	CUMPLE	2025-07-07 19:21:00
1830	5397239	CUMPLE	2025-07-07 19:21:00
1831	5397240	CUMPLE	2025-07-07 19:21:00
1832	5397241	CUMPLE	2025-07-07 19:21:00
1833	5397242	CUMPLE	2025-07-07 19:21:00
1834	4757791	CUMPLE	2025-07-07 19:21:00
1835	2121843	CUMPLE	2025-07-07 19:21:00
1836	4866393	CUMPLE	2025-07-07 19:21:00
1837	5086600	CUMPLE	2025-07-07 19:21:00
1838	5467144	CUMPLE	2025-07-07 19:21:00
1839	2141857	CUMPLE	2025-07-07 19:21:00
1840	5038069	CUMPLE	2025-07-07 19:21:00
1841	5038070	CUMPLE	2025-07-07 19:21:00
1842	5038094	CUMPLE	2025-07-07 19:21:00
1843	5038096	CUMPLE	2025-07-07 19:21:00
1844	5397169	CUMPLE	2025-07-07 19:21:00
1845	5397174	CUMPLE	2025-07-07 19:21:00
1846	5397176	CUMPLE	2025-07-07 19:21:00
1847	2130174	CUMPLE	2025-07-07 19:21:00
1848	4243495	NO CUMPLE	2025-07-07 19:21:00
1849	5008907	NO CUMPLE	2025-07-07 19:21:00
1850	4228800	NO CUMPLE	2025-07-07 19:21:00
1851	5058062	NO CUMPLE	2025-07-07 19:21:00
1852	4878643	NO CUMPLE	2025-07-07 19:21:00
1853	5065124	NO CUMPLE	2025-07-07 19:21:00
1854	4434835	NO CUMPLE	2025-07-07 19:21:00
1855	5280836	NO CUMPLE	2025-07-07 19:21:00
1856	5395490	NO CUMPLE	2025-07-07 19:21:00
1857	1840226	NO CUMPLE	2025-07-07 19:21:00
1858	1840228	NO CUMPLE	2025-07-07 19:21:00
1859	4870634	NO CUMPLE	2025-07-07 19:21:00
1860	2942444	NO CUMPLE	2025-07-07 19:21:00
1861	2942445	NO CUMPLE	2025-07-07 19:21:00
1862	2942446	NO CUMPLE	2025-07-07 19:21:00
1863	4032796	NO CUMPLE	2025-07-07 19:21:00
1864	4032797	NO CUMPLE	2025-07-07 19:21:00
1865	4774078	NO CUMPLE	2025-07-07 19:21:00
1866	4756880	NO CUMPLE	2025-07-07 19:21:00
1867	4001991	CUMPLE	2025-07-07 19:21:00
1868	5367712	CUMPLE	2025-07-07 19:21:00
1869	4944331	CUMPLE	2025-07-07 19:21:00
1870	5145113	CUMPLE	2025-07-07 19:21:00
1871	5145116	CUMPLE	2025-07-07 19:21:00
1872	5319789	CUMPLE	2025-07-07 19:21:00
1873	5404334	CUMPLE	2025-07-07 19:21:00
1874	5354515	CUMPLE	2025-07-07 19:21:00
1875	5174737	CUMPLE	2025-07-07 19:21:00
1876	2536146	NO CUMPLE	2025-07-07 19:21:00
1877	2696896	CUMPLE	2025-07-07 19:21:00
1878	2485010	NO CUMPLE	2025-07-07 19:21:00
1879	5378047	CUMPLE	2025-07-07 19:21:00
1880	2942443	NO CUMPLE	2025-07-07 19:21:00
1881	2942447	NO CUMPLE	2025-07-07 19:21:00
1882	4469104	CUMPLE	2025-07-07 19:21:00
1883	4480788	CUMPLE	2025-07-07 19:21:00
1884	4361429	CUMPLE	2025-07-07 19:21:00
1885	4375764	CUMPLE	2025-07-07 19:21:00
1886	4478722	CUMPLE	2025-07-07 19:21:00
1887	4227421	NO CUMPLE	2025-07-07 19:21:00
1888	4379005	NO CUMPLE	2025-07-07 19:21:00
1889	4189645	CUMPLE	2025-07-07 19:21:00
1890	4565931	CUMPLE	2025-07-07 19:21:00
1891	4693472	NO CUMPLE	2025-07-07 19:21:00
1892	5044685	CUMPLE	2025-07-07 19:21:00
1893	5055367	NO CUMPLE	2025-07-07 19:21:00
1894	5055378	CUMPLE	2025-07-07 19:21:00
1895	5400027	CUMPLE	2025-07-07 19:21:00
1896	5400047	CUMPLE	2025-07-07 19:21:00
1897	5400048	CUMPLE	2025-07-07 19:21:00
1898	5400049	CUMPLE	2025-07-07 19:21:00
1899	5400050	CUMPLE	2025-07-07 19:21:00
1900	5400059	CUMPLE	2025-07-07 19:21:00
1901	5411167	CUMPLE	2025-07-07 19:21:00
1902	5411168	CUMPLE	2025-07-07 19:21:00
1903	5411169	CUMPLE	2025-07-07 19:21:00
1904	5411170	CUMPLE	2025-07-07 19:21:00
1905	5411172	CUMPLE	2025-07-07 19:21:00
1906	5563856	CUMPLE	2025-07-07 19:21:00
1907	4545841	NO CUMPLE	2025-07-07 19:21:00
1908	4545897	CUMPLE	2025-07-07 19:21:00
1909	2747953	NO CUMPLE	2025-07-07 19:21:00
1910	4320725	NO CUMPLE	2025-07-07 19:21:00
1911	4320727	NO CUMPLE	2025-07-07 19:21:00
1912	4350238	NO CUMPLE	2025-07-07 19:21:00
1913	4350239	NO CUMPLE	2025-07-07 19:21:00
1914	4878642	NO CUMPLE	2025-07-07 19:21:00
1915	5397243	CUMPLE	2025-07-07 19:21:00
1916	5397244	CUMPLE	2025-07-07 19:21:00
1917	5397246	CUMPLE	2025-07-07 19:21:00
1918	5397247	CUMPLE	2025-07-07 19:21:00
1919	5397248	CUMPLE	2025-07-07 19:21:00
1920	5397249	CUMPLE	2025-07-07 19:21:00
1921	5397250	CUMPLE	2025-07-07 19:21:00
1922	5397251	CUMPLE	2025-07-07 19:21:00
1923	4596312	NO CUMPLE	2025-07-07 19:21:00
1924	4290368	CUMPLE	2025-07-07 19:21:00
1925	4290369	CUMPLE	2025-07-07 19:21:00
1926	4290370	CUMPLE	2025-07-07 19:21:00
1927	4083844	CUMPLE	2025-07-07 19:21:00
1928	5045362	CUMPLE	2025-07-07 19:21:00
1929	2657110	NO CUMPLE	2025-07-07 19:21:00
1930	2657113	CUMPLE	2025-07-07 19:21:00
1931	4467400	CUMPLE	2025-07-07 19:21:00
1932	5393308	CUMPLE	2025-07-07 19:21:00
1933	5393309	CUMPLE	2025-07-07 19:21:00
1934	5393310	CUMPLE	2025-07-07 19:21:00
1935	5393311	CUMPLE	2025-07-07 19:21:00
1936	5447838	CUMPLE	2025-07-07 19:21:00
1937	5449717	CUMPLE	2025-07-07 19:21:00
1938	2885355	CUMPLE	2025-07-07 19:21:00
1939	2885361	CUMPLE	2025-07-07 19:21:00
1940	4776662	CUMPLE	2025-07-07 19:21:00
1941	5205571	CUMPLE	2025-07-07 19:21:00
1942	5542274	CUMPLE	2025-07-07 19:21:00
1943	4717928	CUMPLE	2025-07-07 19:21:00
1944	5153971	CUMPLE	2025-07-07 19:21:00
1945	5397167	CUMPLE	2025-07-07 19:21:00
1946	5397171	CUMPLE	2025-07-07 19:21:00
1947	5133810	CUMPLE	2025-07-07 19:21:00
1948	4195053	CUMPLE	2025-07-07 19:21:00
1949	4215677	CUMPLE	2025-07-07 19:21:00
1950	4215594	CUMPLE	2025-07-07 19:21:00
1951	4215592	CUMPLE	2025-07-07 19:21:00
1952	4357717	NO CUMPLE	2025-07-07 19:21:00
1953	5417976	CUMPLE	2025-07-07 19:21:00
1954	5417977	CUMPLE	2025-07-07 19:21:00
1955	5417979	CUMPLE	2025-07-07 19:21:00
1956	5417980	CUMPLE	2025-07-07 19:21:00
1957	5379977	CUMPLE	2025-07-07 19:21:00
1958	5429231	CUMPLE	2025-07-07 19:21:00
1959	4468927	CUMPLE	2025-07-07 19:21:00
1960	4468928	CUMPLE	2025-07-07 19:21:00
1961	4468929	CUMPLE	2025-07-07 19:21:00
1962	4878678	NO CUMPLE	2025-07-07 19:21:00
1963	4878679	NO CUMPLE	2025-07-07 19:21:00
1964	4878680	NO CUMPLE	2025-07-07 19:21:00
1965	2987531	CUMPLE	2025-07-07 19:21:00
1966	4083854	CUMPLE	2025-07-07 19:21:00
1967	4231201	NO CUMPLE	2025-07-07 19:21:00
1968	4351397	CUMPLE	2025-07-07 19:21:00
1969	4271870	CUMPLE	2025-07-07 19:21:00
1970	2971289	NO CUMPLE	2025-07-07 19:21:00
1971	4701214	CUMPLE	2025-07-07 19:21:00
1972	4701213	CUMPLE	2025-07-07 19:21:00
1973	5193992	NO CUMPLE	2025-07-07 19:21:00
1974	4072726	CUMPLE	2025-07-07 19:21:00
1975	4455299	CUMPLE	2025-07-07 19:21:00
1976	2663481	CUMPLE	2025-07-07 19:21:00
1977	2504728	NO CUMPLE	2025-07-07 19:21:00
1978	4335198	CUMPLE	2025-07-07 19:21:00
1979	4909571	CUMPLE	2025-07-07 19:21:00
1980	5185629	CUMPLE	2025-07-07 19:21:00
1981	4525730	NO CUMPLE	2025-07-07 19:21:00
1982	4846275	CUMPLE	2025-07-07 19:21:00
1983	5426914	CUMPLE	2025-07-07 19:21:00
1984	2938694	CUMPLE	2025-07-07 19:21:00
1985	4027245	CUMPLE	2025-07-07 19:21:00
1986	4523618	NO CUMPLE	2025-07-07 19:21:00
1987	2657109	CUMPLE	2025-07-07 19:21:00
1988	4713545	CUMPLE	2025-07-07 19:21:00
1989	5185634	CUMPLE	2025-07-07 19:21:00
1990	2999805	NO CUMPLE	2025-07-07 19:21:00
1991	4845001	NO CUMPLE	2025-07-07 19:21:00
1992	4702493	CUMPLE	2025-07-07 19:21:00
1993	5024224	CUMPLE	2025-07-07 19:21:00
1994	4714382	CUMPLE	2025-07-07 19:21:00
1995	4714384	CUMPLE	2025-07-07 19:21:00
1996	5378048	CUMPLE	2025-07-07 19:21:00
1997	5378049	CUMPLE	2025-07-07 19:21:00
1998	5378050	CUMPLE	2025-07-07 19:21:00
1999	5378051	CUMPLE	2025-07-07 19:21:00
2000	2695719	NO CUMPLE	2025-07-07 19:21:00
2001	5086393	CUMPLE	2025-07-07 19:21:00
2002	5086395	CUMPLE	2025-07-07 19:21:00
2003	5086397	CUMPLE	2025-07-07 19:21:00
2004	5086399	NO CUMPLE	2025-07-07 19:21:00
2005	4156016	CUMPLE	2025-07-07 19:21:00
2006	4156018	CUMPLE	2025-07-07 19:21:00
2007	5528275	CUMPLE	2025-07-07 19:21:00
2008	5436282	CUMPLE	2025-07-07 19:21:00
2009	5436283	CUMPLE	2025-07-07 19:21:00
2010	5397168	CUMPLE	2025-07-07 19:21:00
2011	4331021	CUMPLE	2025-07-07 19:21:00
2012	5514156	CUMPLE	2025-07-07 19:21:00
2013	4402417	CUMPLE	2025-07-07 19:21:00
2014	4393055	CUMPLE	2025-07-07 19:21:00
2015	4393054	CUMPLE	2025-07-07 19:21:00
2016	4393052	CUMPLE	2025-07-07 19:21:00
2017	4393050	CUMPLE	2025-07-07 19:21:00
2018	5436901	CUMPLE	2025-07-07 19:21:00
2019	5436899	CUMPLE	2025-07-07 19:21:00
2020	5436897	CUMPLE	2025-07-07 19:21:00
2021	5436895	CUMPLE	2025-07-07 19:21:00
2022	5436893	CUMPLE	2025-07-07 19:21:00
2023	5436891	CUMPLE	2025-07-07 19:21:00
2024	5436889	CUMPLE	2025-07-07 19:21:00
2025	5436887	CUMPLE	2025-07-07 19:21:00
2026	4341838	CUMPLE	2025-07-07 19:21:00
2027	4341836	CUMPLE	2025-07-07 19:21:00
2028	4341835	CUMPLE	2025-07-07 19:21:00
2029	4341833	CUMPLE	2025-07-07 19:21:00
2030	2508862	CUMPLE	2025-07-07 19:21:00
2031	2755533	NO CUMPLE	2025-07-07 19:21:00
2032	2755549	CUMPLE	2025-07-07 19:21:00
2033	2712536	NO CUMPLE	2025-07-07 19:21:00
2034	5407153	NO CUMPLE	2025-07-07 19:21:00
2035	4243478	NO CUMPLE	2025-07-07 19:21:00
2036	5400028	CUMPLE	2025-07-07 19:21:00
2037	4718098	CUMPLE	2025-07-07 19:21:00
2038	5426915	NO CUMPLE	2025-07-07 19:21:00
2039	4523619	NO CUMPLE	2025-07-07 19:21:00
2040	5064899	CUMPLE	2025-07-07 19:21:00
2041	5375927	CUMPLE	2025-07-07 19:21:00
2042	5375928	CUMPLE	2025-07-07 19:21:00
2043	5375929	CUMPLE	2025-07-07 19:21:00
2044	4174545	NO CUMPLE	2025-07-07 19:21:00
2045	4174546	NO CUMPLE	2025-07-07 19:21:00
2046	4174547	NO CUMPLE	2025-07-07 19:21:00
2047	4174552	NO CUMPLE	2025-07-07 19:21:00
2048	2217050	NO CUMPLE	2025-07-07 19:21:00
2049	4755780	NO CUMPLE	2025-07-07 19:21:00
2050	4755776	NO CUMPLE	2025-07-07 19:21:00
2051	2529420	NO CUMPLE	2025-07-07 19:21:00
2052	2529419	NO CUMPLE	2025-07-07 19:21:00
2053	2529418	NO CUMPLE	2025-07-07 19:21:00
2054	2529417	NO CUMPLE	2025-07-07 19:21:00
2055	2529416	NO CUMPLE	2025-07-07 19:21:00
2056	2605177	NO CUMPLE	2025-07-07 19:21:00
2057	2605176	NO CUMPLE	2025-07-07 19:21:00
2058	2605175	NO CUMPLE	2025-07-07 19:21:00
2059	2605174	NO CUMPLE	2025-07-07 19:21:00
2060	2605173	NO CUMPLE	2025-07-07 19:21:00
2061	2432297	NO CUMPLE	2025-07-07 19:21:00
2062	2432295	NO CUMPLE	2025-07-07 19:21:00
2063	2987085	NO CUMPLE	2025-07-07 19:21:00
2064	4808761	NO CUMPLE	2025-07-07 19:21:00
2065	2743985	NO CUMPLE	2025-07-07 19:21:00
2066	2608434	NO CUMPLE	2025-07-07 19:21:00
2067	2608435	NO CUMPLE	2025-07-07 19:21:00
2068	2608433	NO CUMPLE	2025-07-07 19:21:00
2069	2608432	NO CUMPLE	2025-07-07 19:21:00
2070	2608431	NO CUMPLE	2025-07-07 19:21:00
2071	5174599	CUMPLE	2025-07-07 19:21:00
2072	2456538	NO CUMPLE	2025-07-07 19:21:00
2073	4603904	NO CUMPLE	2025-07-07 19:21:00
2074	4597059	NO CUMPLE	2025-07-07 19:21:00
2075	4808703	NO CUMPLE	2025-07-07 19:21:00
2076	4144250	CUMPLE	2025-07-07 19:21:00
2077	4144251	CUMPLE	2025-07-07 19:21:00
2078	4144252	CUMPLE	2025-07-07 19:21:00
2079	4144253	CUMPLE	2025-07-07 19:21:00
2080	4144254	CUMPLE	2025-07-07 19:21:00
2081	4386873	NO CUMPLE	2025-07-07 19:21:00
2082	5185485	CUMPLE	2025-07-07 19:21:00
2083	5185487	CUMPLE	2025-07-07 19:21:00
2084	5185488	CUMPLE	2025-07-07 19:21:00
2085	5516906	CUMPLE	2025-07-07 19:21:00
2086	885258	NO CUMPLE	2025-07-07 19:21:00
2087	4977237	NO CUMPLE	2025-07-07 19:21:00
2088	4301344	CUMPLE	2025-07-07 19:21:00
2089	4788536	NO CUMPLE	2025-07-07 19:21:00
2090	4788537	NO CUMPLE	2025-07-07 19:21:00
2091	4788538	NO CUMPLE	2025-07-07 19:21:00
2092	5446996	CUMPLE	2025-07-07 19:21:00
2093	5446999	CUMPLE	2025-07-07 19:21:00
2094	5447002	CUMPLE	2025-07-07 19:21:00
2095	4883185	CUMPLE	2025-07-07 19:21:00
2096	4883189	CUMPLE	2025-07-07 19:21:00
2097	4434400	NO CUMPLE	2025-07-07 19:21:00
2098	4748981	CUMPLE	2025-07-07 19:21:00
2099	4748983	CUMPLE	2025-07-07 19:21:00
2100	4748984	CUMPLE	2025-07-07 19:21:00
2101	4748985	CUMPLE	2025-07-07 19:21:00
2102	5415167	CUMPLE	2025-07-07 19:21:00
2103	5415171	CUMPLE	2025-07-07 19:21:00
2104	2556248	NO CUMPLE	2025-07-07 19:21:00
2105	2556253	NO CUMPLE	2025-07-07 19:21:00
2106	5045657	CUMPLE	2025-07-07 19:21:00
2107	5415092	CUMPLE	2025-07-07 19:21:00
2108	5415093	CUMPLE	2025-07-07 19:21:00
2109	5425886	CUMPLE	2025-07-07 19:21:00
2110	4905569	CUMPLE	2025-07-07 19:21:00
2111	4863777	NO CUMPLE	2025-07-07 19:21:00
2112	4237465	NO CUMPLE	2025-07-07 19:21:00
2113	4844355	CUMPLE	2025-07-07 19:21:00
2114	4967631	CUMPLE	2025-07-07 19:21:00
2115	4758867	CUMPLE	2025-07-07 19:21:00
2116	5039692	NO CUMPLE	2025-07-07 19:21:00
2117	5039694	NO CUMPLE	2025-07-07 19:21:00
2118	5039695	NO CUMPLE	2025-07-07 19:21:00
2119	4808765	NO CUMPLE	2025-07-07 19:21:00
2120	4227420	CUMPLE	2025-07-07 19:21:00
2121	4883812	NO CUMPLE	2025-07-07 19:21:00
2122	4308283	NO CUMPLE	2025-07-07 19:21:00
2123	5416941	CUMPLE	2025-07-07 19:21:00
2124	4237468	CUMPLE	2025-07-07 19:21:00
2125	4870148	CUMPLE	2025-07-07 19:21:00
2126	2692853	NO CUMPLE	2025-07-07 19:21:00
2127	2978874	CUMPLE	2025-07-07 19:21:00
2128	5426109	CUMPLE	2025-07-07 19:21:00
2129	5426112	CUMPLE	2025-07-07 19:21:00
2130	5367718	CUMPLE	2025-07-07 19:21:00
2131	4560120	NO CUMPLE	2025-07-07 19:21:00
2132	4944335	CUMPLE	2025-07-07 19:21:00
2133	5447635	CUMPLE	2025-07-07 19:21:00
2134	4261781	NO CUMPLE	2025-07-07 19:21:00
2135	5064188	NO CUMPLE	2025-07-07 19:21:00
2136	4560112	NO CUMPLE	2025-07-07 19:21:00
2137	4560168	NO CUMPLE	2025-07-07 19:21:00
2138	4566692	NO CUMPLE	2025-07-07 19:21:00
2139	4844998	NO CUMPLE	2025-07-07 19:21:00
2140	4845000	NO CUMPLE	2025-07-07 19:21:00
2141	4870152	CUMPLE	2025-07-07 19:21:00
2142	5185630	CUMPLE	2025-07-07 19:21:00
2143	5405208	CUMPLE	2025-07-07 19:21:00
2144	4757504	NO CUMPLE	2025-07-07 19:21:00
2145	4846294	CUMPLE	2025-07-07 19:21:00
2146	5187566	NO CUMPLE	2025-07-07 19:21:00
2147	5187567	NO CUMPLE	2025-07-07 19:21:00
2148	5187568	NO CUMPLE	2025-07-07 19:21:00
2149	4233887	NO CUMPLE	2025-07-07 19:21:00
2150	5406939	CUMPLE	2025-07-07 19:21:00
2151	4373931	NO CUMPLE	2025-07-07 19:21:00
2152	4537591	CUMPLE	2025-07-07 19:21:00
2153	5055813	CUMPLE	2025-07-07 19:21:00
2154	5319788	CUMPLE	2025-07-07 19:21:00
2155	4773297	CUMPLE	2025-07-07 19:21:00
2156	4773298	CUMPLE	2025-07-07 19:21:00
2157	4814031	CUMPLE	2025-07-07 19:21:00
2158	2714806	CUMPLE	2025-07-07 19:21:00
2159	4878682	CUMPLE	2025-07-07 19:21:00
2160	5205573	CUMPLE	2025-07-07 19:21:00
2161	4233072	NO CUMPLE	2025-07-07 19:21:00
2162	2648471	NO CUMPLE	2025-07-07 19:21:00
2163	2648470	NO CUMPLE	2025-07-07 19:21:00
2164	5445456	NO CUMPLE	2025-07-07 19:21:00
2165	4808565	NO CUMPLE	2025-07-07 19:21:00
2166	2173353	NO CUMPLE	2025-07-07 19:21:00
2167	2173352	NO CUMPLE	2025-07-07 19:21:00
2168	2173351	NO CUMPLE	2025-07-07 19:21:00
2169	2308218	NO CUMPLE	2025-07-07 19:21:00
2170	2173349	NO CUMPLE	2025-07-07 19:21:00
2171	2173348	NO CUMPLE	2025-07-07 19:21:00
2172	2173347	NO CUMPLE	2025-07-07 19:21:00
2173	2308148	NO CUMPLE	2025-07-07 19:21:00
2174	2308147	NO CUMPLE	2025-07-07 19:21:00
2175	2172052	NO CUMPLE	2025-07-07 19:21:00
2176	2172051	NO CUMPLE	2025-07-07 19:21:00
2177	2630631	NO CUMPLE	2025-07-07 19:21:00
2178	2461443	NO CUMPLE	2025-07-07 19:21:00
2179	5245475	NO CUMPLE	2025-07-07 19:21:00
2180	2577409	NO CUMPLE	2025-07-07 19:21:00
2181	2577407	NO CUMPLE	2025-07-07 19:21:00
2182	1862927	NO CUMPLE	2025-07-07 19:21:00
2183	1862926	NO CUMPLE	2025-07-07 19:21:00
2184	2415067	NO CUMPLE	2025-07-07 19:21:00
2185	2415066	NO CUMPLE	2025-07-07 19:21:00
2186	2415065	NO CUMPLE	2025-07-07 19:21:00
2187	2308196	NO CUMPLE	2025-07-07 19:21:00
2188	5013834	CUMPLE	2025-07-07 19:21:00
2189	5013835	CUMPLE	2025-07-07 19:21:00
2190	5013838	CUMPLE	2025-07-07 19:21:00
2191	5013839	CUMPLE	2025-07-07 19:21:00
2192	5224362	CUMPLE	2025-07-07 19:21:00
2193	4964788	CUMPLE	2025-07-07 19:21:00
2194	2837835	CUMPLE	2025-07-07 19:21:00
2195	4478543	CUMPLE	2025-07-07 19:21:00
2196	4478544	CUMPLE	2025-07-07 19:21:00
2197	4478545	CUMPLE	2025-07-07 19:21:00
2198	4756793	CUMPLE	2025-07-07 19:21:00
2199	4756795	CUMPLE	2025-07-07 19:21:00
2200	2730860	CUMPLE	2025-07-07 19:21:00
2201	2730864	CUMPLE	2025-07-07 19:21:00
2202	2730866	CUMPLE	2025-07-07 19:21:00
2203	2730868	CUMPLE	2025-07-07 19:21:00
2204	5316909	CUMPLE	2025-07-07 19:21:00
2205	5515636	CUMPLE	2025-07-07 19:21:00
2206	5515637	CUMPLE	2025-07-07 19:21:00
2207	5515639	CUMPLE	2025-07-07 19:21:00
2208	5515640	CUMPLE	2025-07-07 19:21:00
2209	5524909	CUMPLE	2025-07-07 19:21:00
2210	2695429	CUMPLE	2025-07-07 19:21:00
2211	2695430	CUMPLE	2025-07-07 19:21:00
2212	5436320	CUMPLE	2025-07-07 19:21:00
2213	5436325	CUMPLE	2025-07-07 19:21:00
2214	4127870	CUMPLE	2025-07-07 19:21:00
2215	4569187	CUMPLE	2025-07-07 19:21:00
2216	4569188	CUMPLE	2025-07-07 19:21:00
2217	4569189	CUMPLE	2025-07-07 19:21:00
2218	4569190	CUMPLE	2025-07-07 19:21:00
2219	4569191	CUMPLE	2025-07-07 19:21:00
2220	4814035	CUMPLE	2025-07-07 19:21:00
2221	4839661	CUMPLE	2025-07-07 19:21:00
2222	4864129	CUMPLE	2025-07-07 19:21:00
2223	4864130	CUMPLE	2025-07-07 19:21:00
2224	4878779	CUMPLE	2025-07-07 19:21:00
2225	4878780	CUMPLE	2025-07-07 19:21:00
2226	4879843	CUMPLE	2025-07-07 19:21:00
2227	4879991	CUMPLE	2025-07-07 19:21:00
2228	5010379	CUMPLE	2025-07-07 19:21:00
2229	5205665	CUMPLE	2025-07-07 19:21:00
2230	5205666	CUMPLE	2025-07-07 19:21:00
2231	5205668	CUMPLE	2025-07-07 19:21:00
2232	5205669	CUMPLE	2025-07-07 19:21:00
2233	5404335	CUMPLE	2025-07-07 19:21:00
2234	5185624	CUMPLE	2025-07-07 19:21:00
2235	5355235	CUMPLE	2025-07-07 19:21:00
2236	2546104	CUMPLE	2025-07-07 19:21:00
2237	2546106	CUMPLE	2025-07-07 19:21:00
2238	4192770	CUMPLE	2025-07-07 19:21:00
2239	4589867	NO CUMPLE	2025-07-07 19:21:00
2240	4589869	NO CUMPLE	2025-07-07 19:21:00
2241	4866439	CUMPLE	2025-07-07 19:21:00
2242	5264077	CUMPLE	2025-07-07 19:21:00
2243	5355728	CUMPLE	2025-07-07 19:21:00
2244	5355731	CUMPLE	2025-07-07 19:21:00
2245	5355733	CUMPLE	2025-07-07 19:21:00
2246	5355734	CUMPLE	2025-07-07 19:21:00
2247	5355735	CUMPLE	2025-07-07 19:21:00
2248	4228801	CUMPLE	2025-07-07 19:21:00
2249	5416938	CUMPLE	2025-07-07 19:21:00
2250	5426916	CUMPLE	2025-07-07 19:21:00
2251	2916395	CUMPLE	2025-07-07 19:21:00
2252	4320610	CUMPLE	2025-07-07 19:21:00
2253	4320726	CUMPLE	2025-07-07 19:21:00
2254	4320728	CUMPLE	2025-07-07 19:21:00
2255	4320730	CUMPLE	2025-07-07 19:21:00
2256	4350234	CUMPLE	2025-07-07 19:21:00
2257	4847337	CUMPLE	2025-07-07 19:21:00
2258	4847340	CUMPLE	2025-07-07 19:21:00
2259	4847341	CUMPLE	2025-07-07 19:21:00
2260	5393691	CUMPLE	2025-07-07 19:21:00
2261	5393692	CUMPLE	2025-07-07 19:21:00
2262	5393693	CUMPLE	2025-07-07 19:21:00
2263	5393694	CUMPLE	2025-07-07 19:21:00
2264	5393695	CUMPLE	2025-07-07 19:21:00
2265	5393696	CUMPLE	2025-07-07 19:21:00
2266	5404622	CUMPLE	2025-07-07 19:21:00
2267	5404624	CUMPLE	2025-07-07 19:21:00
2268	5415305	CUMPLE	2025-07-07 19:21:00
2269	5415806	CUMPLE	2025-07-07 19:21:00
2270	5415807	CUMPLE	2025-07-07 19:21:00
2271	5415808	CUMPLE	2025-07-07 19:21:00
2272	5415809	CUMPLE	2025-07-07 19:21:00
2273	5415810	CUMPLE	2025-07-07 19:21:00
2274	5365018	CUMPLE	2025-07-07 19:21:00
2275	4905568	CUMPLE	2025-07-07 19:21:00
2276	4905572	CUMPLE	2025-07-07 19:21:00
2277	5275185	CUMPLE	2025-07-07 19:21:00
2278	5275186	CUMPLE	2025-07-07 19:21:00
2279	4866389	CUMPLE	2025-07-07 19:21:00
2280	4866390	CUMPLE	2025-07-07 19:21:00
2281	5467154	CUMPLE	2025-07-07 19:21:00
2282	4170010	CUMPLE	2025-07-07 19:21:00
2283	5187815	CUMPLE	2025-07-07 19:21:00
2284	5426105	CUMPLE	2025-07-07 19:21:00
2285	5426106	CUMPLE	2025-07-07 19:21:00
2286	2902991	CUMPLE	2025-07-07 19:21:00
2287	5074665	CUMPLE	2025-07-07 19:21:00
2288	5074496	CUMPLE	2025-07-07 19:21:00
2289	5074497	CUMPLE	2025-07-07 19:21:00
2290	5404609	CUMPLE	2025-07-07 19:21:00
2291	5404611	CUMPLE	2025-07-07 19:21:00
2292	4785690	CUMPLE	2025-07-07 19:21:00
2293	4327106	CUMPLE	2025-07-07 19:21:00
2294	4108972	CUMPLE	2025-07-07 19:21:00
2295	2651141	CUMPLE	2025-07-07 19:21:00
2296	5306725	CUMPLE	2025-07-07 19:21:00
2297	5306726	CUMPLE	2025-07-07 19:21:00
2298	5306727	CUMPLE	2025-07-07 19:21:00
2299	5306728	CUMPLE	2025-07-07 19:21:00
2300	5306729	CUMPLE	2025-07-07 19:21:00
2301	5205548	CUMPLE	2025-07-07 19:21:00
2302	4214746	CUMPLE	2025-07-07 19:21:00
2303	4887679	CUMPLE	2025-07-07 19:21:00
2304	5057058	CUMPLE	2025-07-07 19:21:00
2305	2617515	NO CUMPLE	2025-07-07 19:21:00
2306	4282914	CUMPLE	2025-07-07 19:21:00
2307	2730852	NO CUMPLE	2025-07-07 19:21:00
2308	2695428	CUMPLE	2025-07-07 19:21:00
2309	2734837	CUMPLE	2025-07-07 19:21:00
2310	2764319	NO CUMPLE	2025-07-07 19:21:00
2311	4898423	NO CUMPLE	2025-07-07 19:21:00
2312	4923843	NO CUMPLE	2025-07-07 19:21:00
2313	2546103	CUMPLE	2025-07-07 19:21:00
2314	4866441	CUMPLE	2025-07-07 19:21:00
2315	4944333	CUMPLE	2025-07-07 19:21:00
2316	4228805	NO CUMPLE	2025-07-07 19:21:00
2317	4408713	NO CUMPLE	2025-07-07 19:21:00
2318	2505147	NO CUMPLE	2025-07-07 19:21:00
2319	4997641	CUMPLE	2025-07-07 19:21:00
2320	4774326	CUMPLE	2025-07-07 19:21:00
2321	4774327	CUMPLE	2025-07-07 19:21:00
2322	5187817	NO CUMPLE	2025-07-07 19:21:00
2323	4009814	NO CUMPLE	2025-07-07 19:21:00
2324	4825466	NO CUMPLE	2025-07-07 19:21:00
2325	4825467	NO CUMPLE	2025-07-07 19:21:00
2326	83848	NO CUMPLE	2025-07-07 19:21:00
2327	83850	NO CUMPLE	2025-07-07 19:21:00
2328	5224393	CUMPLE	2025-07-07 19:21:00
2329	5224395	NO CUMPLE	2025-07-07 19:21:00
2330	5224396	NO CUMPLE	2025-07-07 19:21:00
2331	5224398	CUMPLE	2025-07-07 19:21:00
2332	4062730	CUMPLE	2025-07-07 19:21:00
2333	2708561	NO CUMPLE	2025-07-07 19:21:00
2334	4887689	CUMPLE	2025-07-07 19:21:00
2335	4586077	NO CUMPLE	2025-07-07 19:21:00
2336	2695431	NO CUMPLE	2025-07-07 19:21:00
2337	2695716	NO CUMPLE	2025-07-07 19:21:00
2338	4293986	NO CUMPLE	2025-07-07 19:21:00
2339	4293988	NO CUMPLE	2025-07-07 19:21:00
2340	4713667	NO CUMPLE	2025-07-07 19:21:00
2341	4146990	CUMPLE	2025-07-07 19:21:00
2342	4400852	CUMPLE	2025-07-07 19:21:00
2343	4693469	CUMPLE	2025-07-07 19:21:00
2344	4693473	CUMPLE	2025-07-07 19:21:00
2345	4878768	CUMPLE	2025-07-07 19:21:00
2346	4878856	CUMPLE	2025-07-07 19:21:00
2347	4944336	CUMPLE	2025-07-07 19:21:00
2348	4967628	NO CUMPLE	2025-07-07 19:21:00
2349	5411277	NO CUMPLE	2025-07-07 19:21:00
2350	4232405	CUMPLE	2025-07-07 19:21:00
2351	4789477	CUMPLE	2025-07-07 19:21:00
2352	4316847	NO CUMPLE	2025-07-07 19:21:00
2353	4336818	NO CUMPLE	2025-07-07 19:21:00
2354	4336854	NO CUMPLE	2025-07-07 19:21:00
2355	4899398	NO CUMPLE	2025-07-07 19:21:00
2356	5280837	NO CUMPLE	2025-07-07 19:21:00
2357	5280838	NO CUMPLE	2025-07-07 19:21:00
2358	4290357	NO CUMPLE	2025-07-07 19:21:00
2359	1685018	NO CUMPLE	2025-07-07 19:21:00
2360	4833706	NO CUMPLE	2025-07-07 19:21:00
2361	5064900	NO CUMPLE	2025-07-07 19:21:00
2362	5064901	NO CUMPLE	2025-07-07 19:21:00
2363	5186162	CUMPLE	2025-07-07 19:21:00
2364	5186165	CUMPLE	2025-07-07 19:21:00
2365	5414191	NO CUMPLE	2025-07-07 19:21:00
2366	5414192	CUMPLE	2025-07-07 19:21:00
2367	5414193	CUMPLE	2025-07-07 19:21:00
2368	5414194	NO CUMPLE	2025-07-07 19:21:00
2369	5414195	CUMPLE	2025-07-07 19:21:00
2370	5447636	CUMPLE	2025-07-07 19:21:00
2371	5540579	CUMPLE	2025-07-07 19:21:00
2372	4450054	CUMPLE	2025-07-07 19:21:00
2373	4908566	NO CUMPLE	2025-07-07 19:21:00
2374	1143839	NO CUMPLE	2025-07-07 19:21:00
2375	5537359	CUMPLE	2025-07-07 19:21:00
2376	5085129	CUMPLE	2025-07-07 19:21:00
2377	5393608	CUMPLE	2025-07-07 19:21:00
2378	5224380	CUMPLE	2025-07-07 19:21:00
2379	5437025	CUMPLE	2025-07-07 19:21:00
2380	2769273	CUMPLE	2025-07-07 19:21:00
2381	4176330	CUMPLE	2025-07-07 19:21:00
2382	4331748	CUMPLE	2025-07-07 19:21:00
2383	2536147	CUMPLE	2025-07-07 19:21:00
2384	2536148	NO CUMPLE	2025-07-07 19:21:00
2385	4109215	CUMPLE	2025-07-07 19:21:00
2386	5407151	NO CUMPLE	2025-07-07 19:21:00
2387	4925499	CUMPLE	2025-07-07 19:21:00
2388	2734836	NO CUMPLE	2025-07-07 19:21:00
2389	2734838	CUMPLE	2025-07-07 19:21:00
2390	2734839	CUMPLE	2025-07-07 19:21:00
2391	2734840	CUMPLE	2025-07-07 19:21:00
2392	4373930	NO CUMPLE	2025-07-07 19:21:00
2393	5223803	NO CUMPLE	2025-07-07 19:21:00
2394	4031948	NO CUMPLE	2025-07-07 19:21:00
2395	4878638	NO CUMPLE	2025-07-07 19:21:00
2396	5065123	NO CUMPLE	2025-07-07 19:21:00
2397	5065125	NO CUMPLE	2025-07-07 19:21:00
2398	4184821	NO CUMPLE	2025-07-07 19:21:00
2399	4361591	NO CUMPLE	2025-07-07 19:21:00
2400	4083848	NO CUMPLE	2025-07-07 19:21:00
2401	4774030	CUMPLE	2025-07-07 19:21:00
2402	5045585	NO CUMPLE	2025-07-07 19:21:00
2403	5187813	NO CUMPLE	2025-07-07 19:21:00
2404	5541932	NO CUMPLE	2025-07-07 19:21:00
2405	2126337	CUMPLE	2025-07-07 19:21:00
2406	4019531	CUMPLE	2025-07-07 19:21:00
2407	5153973	CUMPLE	2025-07-07 19:21:00
2408	5153974	CUMPLE	2025-07-07 19:21:00
2409	4407096	NO CUMPLE	2025-07-07 19:21:00
2410	4997186	NO CUMPLE	2025-07-07 19:21:00
2411	4784077	NO CUMPLE	2025-07-07 19:21:00
2412	2648444	NO CUMPLE	2025-07-07 19:21:00
2413	5275473	NO CUMPLE	2025-07-07 19:21:00
2414	569379	NO CUMPLE	2025-07-07 19:21:00
2415	2942434	NO CUMPLE	2025-07-07 19:21:00
2416	2942435	NO CUMPLE	2025-07-07 19:21:00
2417	2942436	NO CUMPLE	2025-07-07 19:21:00
2418	2942437	NO CUMPLE	2025-07-07 19:21:00
2419	4093970	NO CUMPLE	2025-07-07 19:21:00
2420	4250693	NO CUMPLE	2025-07-07 19:21:00
2421	4304117	NO CUMPLE	2025-07-07 19:21:00
2422	4304119	NO CUMPLE	2025-07-07 19:21:00
2423	4311191	CUMPLE	2025-07-07 19:21:00
2424	4350240	NO CUMPLE	2025-07-07 19:21:00
2425	4400851	NO CUMPLE	2025-07-07 19:21:00
2426	4407895	NO CUMPLE	2025-07-07 19:21:00
2427	4492675	NO CUMPLE	2025-07-07 19:21:00
2428	4492676	NO CUMPLE	2025-07-07 19:21:00
2429	4492677	NO CUMPLE	2025-07-07 19:21:00
2430	4525729	NO CUMPLE	2025-07-07 19:21:00
2431	4698798	NO CUMPLE	2025-07-07 19:21:00
2432	4898467	NO CUMPLE	2025-07-07 19:21:00
2433	4899397	NO CUMPLE	2025-07-07 19:21:00
2434	4899399	NO CUMPLE	2025-07-07 19:21:00
2435	5038065	CUMPLE	2025-07-07 19:21:00
2436	5038066	CUMPLE	2025-07-07 19:21:00
2437	5095424	CUMPLE	2025-07-07 19:21:00
2438	5186163	CUMPLE	2025-07-07 19:21:00
2439	4851785	CUMPLE	2025-07-07 19:21:00
2440	4851789	CUMPLE	2025-07-07 19:21:00
2441	5164451	CUMPLE	2025-07-07 19:21:00
2442	5164452	CUMPLE	2025-07-07 19:21:00
2443	5164453	CUMPLE	2025-07-07 19:21:00
2444	5164592	CUMPLE	2025-07-07 19:21:00
2445	5164593	CUMPLE	2025-07-07 19:21:00
2446	5164594	CUMPLE	2025-07-07 19:21:00
2447	5164595	CUMPLE	2025-07-07 19:21:00
2448	5449275	CUMPLE	2025-07-07 19:21:00
2449	4047278	CUMPLE	2025-07-07 19:21:00
2450	4047284	CUMPLE	2025-07-07 19:21:00
2451	4047286	CUMPLE	2025-07-07 19:21:00
2452	4047288	CUMPLE	2025-07-07 19:21:00
2453	4047290	CUMPLE	2025-07-07 19:21:00
2454	4898244	CUMPLE	2025-07-07 19:21:00
2455	4898245	CUMPLE	2025-07-07 19:21:00
2456	5002702	CUMPLE	2025-07-07 19:21:00
2457	5002704	CUMPLE	2025-07-07 19:21:00
2458	5002706	CUMPLE	2025-07-07 19:21:00
2459	5002708	CUMPLE	2025-07-07 19:21:00
2460	5365140	CUMPLE	2025-07-07 19:21:00
2461	5365142	CUMPLE	2025-07-07 19:21:00
2462	5365144	CUMPLE	2025-07-07 19:21:00
2463	5365146	CUMPLE	2025-07-07 19:21:00
2464	5365148	CUMPLE	2025-07-07 19:21:00
2465	2504711	NO CUMPLE	2025-07-07 19:21:00
2466	2504714	NO CUMPLE	2025-07-07 19:21:00
2467	2652739	CUMPLE	2025-07-07 19:21:00
2468	5375521	NO CUMPLE	2025-07-07 19:21:00
2469	5375522	NO CUMPLE	2025-07-07 19:21:00
2470	5375523	NO CUMPLE	2025-07-07 19:21:00
2471	5375524	NO CUMPLE	2025-07-07 19:21:00
2472	5375525	NO CUMPLE	2025-07-07 19:21:00
2473	5455934	CUMPLE	2025-07-07 19:21:00
2474	5455935	CUMPLE	2025-07-07 19:21:00
2475	5455936	CUMPLE	2025-07-07 19:21:00
2476	5455937	CUMPLE	2025-07-07 19:21:00
2477	5455938	CUMPLE	2025-07-07 19:21:00
2478	5455940	CUMPLE	2025-07-07 19:21:00
2479	4923855	NO CUMPLE	2025-07-07 19:21:00
2480	4923856	NO CUMPLE	2025-07-07 19:21:00
2481	4923858	NO CUMPLE	2025-07-07 19:21:00
2482	4923859	NO CUMPLE	2025-07-07 19:21:00
2483	4966864	CUMPLE	2025-07-07 19:21:00
2484	4340938	NO CUMPLE	2025-07-07 19:21:00
2485	4340939	NO CUMPLE	2025-07-07 19:21:00
2486	4340940	NO CUMPLE	2025-07-07 19:21:00
2487	4340941	NO CUMPLE	2025-07-07 19:21:00
2488	4340942	NO CUMPLE	2025-07-07 19:21:00
2489	4340943	NO CUMPLE	2025-07-07 19:21:00
2490	4340944	NO CUMPLE	2025-07-07 19:21:00
2491	4846299	NO CUMPLE	2025-07-07 19:21:00
2492	4846300	NO CUMPLE	2025-07-07 19:21:00
2493	4062666	NO CUMPLE	2025-07-07 19:21:00
2494	4312661	NO CUMPLE	2025-07-07 19:21:00
2495	4312663	NO CUMPLE	2025-07-07 19:21:00
2496	5056973	NO CUMPLE	2025-07-07 19:21:00
2497	5056975	NO CUMPLE	2025-07-07 19:21:00
2498	4945507	CUMPLE	2025-07-07 19:21:00
2499	4945508	CUMPLE	2025-07-07 19:21:00
2500	5365020	CUMPLE	2025-07-07 19:21:00
2501	4478933	NO CUMPLE	2025-07-07 19:21:00
2502	4994484	CUMPLE	2025-07-07 19:21:00
2503	4994485	CUMPLE	2025-07-07 19:21:00
2504	5085131	CUMPLE	2025-07-07 19:21:00
2505	5206068	CUMPLE	2025-07-07 19:21:00
2506	5206069	CUMPLE	2025-07-07 19:21:00
2507	5206070	CUMPLE	2025-07-07 19:21:00
2508	5206071	CUMPLE	2025-07-07 19:21:00
2509	5206072	CUMPLE	2025-07-07 19:21:00
2510	5234097	CUMPLE	2025-07-07 19:21:00
2511	5234098	CUMPLE	2025-07-07 19:21:00
2512	5234099	CUMPLE	2025-07-07 19:21:00
2513	5234100	CUMPLE	2025-07-07 19:21:00
2514	5234101	CUMPLE	2025-07-07 19:21:00
2515	2956595	CUMPLE	2025-07-07 19:21:00
2516	2956698	CUMPLE	2025-07-07 19:21:00
2517	2985483	CUMPLE	2025-07-07 19:21:00
2518	2391740	NO CUMPLE	2025-07-07 19:21:00
2519	4994334	NO CUMPLE	2025-07-07 19:21:00
2520	2727063	NO CUMPLE	2025-07-07 19:21:00
2521	2617526	CUMPLE	2025-07-07 19:21:00
2522	2982981	CUMPLE	2025-07-07 19:21:00
2523	4031463	NO CUMPLE	2025-07-07 19:21:00
2524	4350638	CUMPLE	2025-07-07 19:21:00
2525	4350639	CUMPLE	2025-07-07 19:21:00
2526	4350640	CUMPLE	2025-07-07 19:21:00
2527	4524333	CUMPLE	2025-07-07 19:21:00
2528	4716026	CUMPLE	2025-07-07 19:21:00
2529	5157083	CUMPLE	2025-07-07 19:21:00
2530	5157085	NO CUMPLE	2025-07-07 19:21:00
2531	5157087	NO CUMPLE	2025-07-07 19:21:00
2532	5157090	NO CUMPLE	2025-07-07 19:21:00
2533	5157092	NO CUMPLE	2025-07-07 19:21:00
2534	5157094	NO CUMPLE	2025-07-07 19:21:00
2535	5164705	NO CUMPLE	2025-07-07 19:21:00
2536	5316910	CUMPLE	2025-07-07 19:21:00
2537	5316911	CUMPLE	2025-07-07 19:21:00
2538	2536878	CUMPLE	2025-07-07 19:21:00
2539	2536879	CUMPLE	2025-07-07 19:21:00
2540	2774633	NO CUMPLE	2025-07-07 19:21:00
2541	2774637	NO CUMPLE	2025-07-07 19:21:00
2542	2774638	NO CUMPLE	2025-07-07 19:21:00
2543	4229889	NO CUMPLE	2025-07-07 19:21:00
2544	4527591	CUMPLE	2025-07-07 19:21:00
2545	2764318	NO CUMPLE	2025-07-07 19:21:00
2546	2764320	NO CUMPLE	2025-07-07 19:21:00
2547	4271704	NO CUMPLE	2025-07-07 19:21:00
2548	4736063	CUMPLE	2025-07-07 19:21:00
2549	4839663	CUMPLE	2025-07-07 19:21:00
2550	4839664	CUMPLE	2025-07-07 19:21:00
2551	4879842	NO CUMPLE	2025-07-07 19:21:00
2552	4923840	NO CUMPLE	2025-07-07 19:21:00
2553	5055892	CUMPLE	2025-07-07 19:21:00
2554	5044791	CUMPLE	2025-07-07 19:21:00
2555	2546102	CUMPLE	2025-07-07 19:21:00
2556	4192900	CUMPLE	2025-07-07 19:21:00
2557	4866433	CUMPLE	2025-07-07 19:21:00
2558	4866437	CUMPLE	2025-07-07 19:21:00
2559	4866445	CUMPLE	2025-07-07 19:21:00
2560	4866447	CUMPLE	2025-07-07 19:21:00
2561	4945003	NO CUMPLE	2025-07-07 19:21:00
2562	5177881	NO CUMPLE	2025-07-07 19:21:00
2563	5404857	CUMPLE	2025-07-07 19:21:00
2564	5411299	CUMPLE	2025-07-07 19:21:00
2565	5411303	NO CUMPLE	2025-07-07 19:21:00
2566	2838006	NO CUMPLE	2025-07-07 19:21:00
2567	2838008	NO CUMPLE	2025-07-07 19:21:00
2568	2922433	NO CUMPLE	2025-07-07 19:21:00
2569	4311241	NO CUMPLE	2025-07-07 19:21:00
2570	4320729	CUMPLE	2025-07-07 19:21:00
2571	4323875	NO CUMPLE	2025-07-07 19:21:00
2572	4323876	NO CUMPLE	2025-07-07 19:21:00
2573	4323878	NO CUMPLE	2025-07-07 19:21:00
2574	4323879	NO CUMPLE	2025-07-07 19:21:00
2575	4523555	NO CUMPLE	2025-07-07 19:21:00
2576	4523556	NO CUMPLE	2025-07-07 19:21:00
2577	4523557	NO CUMPLE	2025-07-07 19:21:00
2578	4523558	NO CUMPLE	2025-07-07 19:21:00
2579	4523559	NO CUMPLE	2025-07-07 19:21:00
2580	4844365	NO CUMPLE	2025-07-07 19:21:00
2581	4897210	NO CUMPLE	2025-07-07 19:21:00
2582	5056990	NO CUMPLE	2025-07-07 19:21:00
2583	5066500	NO CUMPLE	2025-07-07 19:21:00
2584	5393430	CUMPLE	2025-07-07 19:21:00
2585	5393433	CUMPLE	2025-07-07 19:21:00
2586	5393697	CUMPLE	2025-07-07 19:21:00
2587	4005667	NO CUMPLE	2025-07-07 19:21:00
2588	5187528	NO CUMPLE	2025-07-07 19:21:00
2589	5187529	NO CUMPLE	2025-07-07 19:21:00
2590	5187531	NO CUMPLE	2025-07-07 19:21:00
2591	5332857	NO CUMPLE	2025-07-07 19:21:00
2592	5395675	NO CUMPLE	2025-07-07 19:21:00
2593	5395676	NO CUMPLE	2025-07-07 19:21:00
2594	5395677	NO CUMPLE	2025-07-07 19:21:00
2595	5395683	NO CUMPLE	2025-07-07 19:21:00
2596	5395684	NO CUMPLE	2025-07-07 19:21:00
2597	5275191	NO CUMPLE	2025-07-07 19:21:00
2598	5275192	NO CUMPLE	2025-07-07 19:21:00
2599	5275193	NO CUMPLE	2025-07-07 19:21:00
2600	5275194	NO CUMPLE	2025-07-07 19:21:00
2601	5275195	NO CUMPLE	2025-07-07 19:21:00
2602	4801851	CUMPLE	2025-07-07 19:21:00
2603	4194321	CUMPLE	2025-07-07 19:21:00
2604	4312908	NO CUMPLE	2025-07-07 19:21:00
2605	4312914	NO CUMPLE	2025-07-07 19:21:00
2606	4926359	CUMPLE	2025-07-07 19:21:00
2607	4926361	CUMPLE	2025-07-07 19:21:00
2608	5113871	CUMPLE	2025-07-07 19:21:00
2609	4744755	NO CUMPLE	2025-07-07 19:21:00
2610	4050383	NO CUMPLE	2025-07-07 19:21:00
2611	4050386	NO CUMPLE	2025-07-07 19:21:00
2612	5405212	CUMPLE	2025-07-07 19:21:00
2613	5467146	CUMPLE	2025-07-07 19:21:00
2614	4174882	NO CUMPLE	2025-07-07 19:21:00
2615	5064903	CUMPLE	2025-07-07 19:21:00
2616	5397800	CUMPLE	2025-07-07 19:21:00
2617	5426104	NO CUMPLE	2025-07-07 19:21:00
2618	5426107	NO CUMPLE	2025-07-07 19:21:00
2619	5426108	NO CUMPLE	2025-07-07 19:21:00
2620	5426116	NO CUMPLE	2025-07-07 19:21:00
2621	5426117	NO CUMPLE	2025-07-07 19:21:00
2622	5447630	NO CUMPLE	2025-07-07 19:21:00
2623	5528272	NO CUMPLE	2025-07-07 19:21:00
2624	2694282	CUMPLE	2025-07-07 19:21:00
2625	2694284	CUMPLE	2025-07-07 19:21:00
2626	5057088	NO CUMPLE	2025-07-07 19:21:00
2627	5355500	NO CUMPLE	2025-07-07 19:21:00
2628	5355503	NO CUMPLE	2025-07-07 19:21:00
2629	5392916	NO CUMPLE	2025-07-07 19:21:00
2630	4547576	NO CUMPLE	2025-07-07 19:21:00
2631	4231203	CUMPLE	2025-07-07 19:21:00
2632	4451183	NO CUMPLE	2025-07-07 19:21:00
2633	5153969	CUMPLE	2025-07-07 19:21:00
2634	4407093	CUMPLE	2025-07-07 19:21:00
2635	5185636	CUMPLE	2025-07-07 19:21:00
2636	4180045	NO CUMPLE	2025-07-07 19:21:00
2637	4341735	NO CUMPLE	2025-07-07 19:21:00
2638	5486123	NO CUMPLE	2025-07-07 19:21:00
2639	5486124	NO CUMPLE	2025-07-07 19:21:00
2640	5486125	NO CUMPLE	2025-07-07 19:21:00
2641	5486126	NO CUMPLE	2025-07-07 19:21:00
2642	2755985	CUMPLE	2025-07-07 19:21:00
2643	4549663	CUMPLE	2025-07-07 19:21:00
2644	5510926	CUMPLE	2025-07-07 19:21:00
2645	4017515	CUMPLE	2025-07-07 19:21:00
2646	4239045	CUMPLE	2025-07-07 19:21:00
2647	2647942	NO CUMPLE	2025-07-07 19:21:00
2648	2648469	NO CUMPLE	2025-07-07 19:21:00
2649	5185626	CUMPLE	2025-07-07 19:21:00
2650	5395491	NO CUMPLE	2025-07-07 19:21:00
2651	5395492	NO CUMPLE	2025-07-07 19:21:00
2652	5407155	CUMPLE	2025-07-07 19:21:00
2653	5407156	CUMPLE	2025-07-07 19:21:00
2654	2978875	CUMPLE	2025-07-07 19:21:00
2655	2978877	CUMPLE	2025-07-07 19:21:00
2656	4328950	NO CUMPLE	2025-07-07 19:21:00
2657	2714801	CUMPLE	2025-07-07 19:21:00
2658	2714807	CUMPLE	2025-07-07 19:21:00
2659	4359095	CUMPLE	2025-07-07 19:21:00
2660	4878767	CUMPLE	2025-07-07 19:21:00
2661	5273854	CUMPLE	2025-07-07 19:21:00
2662	4966873	CUMPLE	2025-07-07 19:21:00
2663	2910306	NO CUMPLE	2025-07-07 19:21:00
2664	4326474	NO CUMPLE	2025-07-07 19:21:00
2665	4545838	CUMPLE	2025-07-07 19:21:00
2666	2987532	CUMPLE	2025-07-07 19:21:00
2667	2940557	NO CUMPLE	2025-07-07 19:21:00
2668	2658275	NO CUMPLE	2025-07-07 19:21:00
2669	4866394	CUMPLE	2025-07-07 19:21:00
2670	4866395	CUMPLE	2025-07-07 19:21:00
2671	5393299	CUMPLE	2025-07-07 19:21:00
2672	5393313	CUMPLE	2025-07-07 19:21:00
2673	4559928	CUMPLE	2025-07-07 19:21:00
2674	4904635	CUMPLE	2025-07-07 19:21:00
2675	4735703	NO CUMPLE	2025-07-07 19:21:00
2676	2963895	CUMPLE	2025-07-07 19:21:00
2677	5510954	CUMPLE	2025-07-07 19:21:00
2678	5255930	CUMPLE	2025-07-07 19:21:00
2679	5515638	CUMPLE	2025-07-07 19:21:00
2680	4756794	CUMPLE	2025-07-07 19:21:00
2681	4756796	CUMPLE	2025-07-07 19:21:00
2682	4756797	CUMPLE	2025-07-07 19:21:00
2683	4023120	CUMPLE	2025-07-07 19:21:00
2684	4287456	CUMPLE	2025-07-07 19:21:00
2685	4762196	NO CUMPLE	2025-07-07 19:21:00
2686	4762197	NO CUMPLE	2025-07-07 19:21:00
2687	4762433	NO CUMPLE	2025-07-07 19:21:00
2688	4546548	NO CUMPLE	2025-07-07 19:21:00
2689	5436321	CUMPLE	2025-07-07 19:21:00
2690	5436322	CUMPLE	2025-07-07 19:21:00
2691	5436323	CUMPLE	2025-07-07 19:21:00
2692	5436324	CUMPLE	2025-07-07 19:21:00
2693	4009575	CUMPLE	2025-07-07 19:21:00
2694	4243480	CUMPLE	2025-07-07 19:21:00
2695	5344149	CUMPLE	2025-07-07 19:21:00
2696	5344150	CUMPLE	2025-07-07 19:21:00
2697	5344151	CUMPLE	2025-07-07 19:21:00
2698	5344152	CUMPLE	2025-07-07 19:21:00
2699	5344153	CUMPLE	2025-07-07 19:21:00
2700	5355228	CUMPLE	2025-07-07 19:21:00
2701	5355229	CUMPLE	2025-07-07 19:21:00
2702	5355233	CUMPLE	2025-07-07 19:21:00
2703	5355234	CUMPLE	2025-07-07 19:21:00
2704	4192772	CUMPLE	2025-07-07 19:21:00
2705	4433707	NO CUMPLE	2025-07-07 19:21:00
2706	4589868	NO CUMPLE	2025-07-07 19:21:00
2707	4851632	CUMPLE	2025-07-07 19:21:00
2708	4851633	CUMPLE	2025-07-07 19:21:00
2709	4851634	CUMPLE	2025-07-07 19:21:00
2710	4851635	CUMPLE	2025-07-07 19:21:00
2711	4851637	CUMPLE	2025-07-07 19:21:00
2712	4851638	CUMPLE	2025-07-07 19:21:00
2713	4944999	CUMPLE	2025-07-07 19:21:00
2714	4945000	CUMPLE	2025-07-07 19:21:00
2715	4945001	CUMPLE	2025-07-07 19:21:00
2716	4945002	CUMPLE	2025-07-07 19:21:00
2717	4967629	CUMPLE	2025-07-07 19:21:00
2718	4844390	NO CUMPLE	2025-07-07 19:21:00
2719	4844391	NO CUMPLE	2025-07-07 19:21:00
2720	4844392	NO CUMPLE	2025-07-07 19:21:00
2721	4844393	NO CUMPLE	2025-07-07 19:21:00
2722	4844394	NO CUMPLE	2025-07-07 19:21:00
2723	4844395	NO CUMPLE	2025-07-07 19:21:00
2724	5065121	CUMPLE	2025-07-07 19:21:00
2725	4905570	CUMPLE	2025-07-07 19:21:00
2726	5039690	NO CUMPLE	2025-07-07 19:21:00
2727	5039696	NO CUMPLE	2025-07-07 19:21:00
2728	5039697	NO CUMPLE	2025-07-07 19:21:00
2729	5039698	NO CUMPLE	2025-07-07 19:21:00
2730	5447535	CUMPLE	2025-07-07 19:21:00
2731	5447539	CUMPLE	2025-07-07 19:21:00
2732	5447540	CUMPLE	2025-07-07 19:21:00
2733	5447541	CUMPLE	2025-07-07 19:21:00
2734	5447542	CUMPLE	2025-07-07 19:21:00
2735	5511797	CUMPLE	2025-07-07 19:21:00
2736	4374779	CUMPLE	2025-07-07 19:21:00
2737	5153970	CUMPLE	2025-07-07 19:21:00
2738	5153972	CUMPLE	2025-07-07 19:21:00
2739	2538918	CUMPLE	2025-07-07 19:21:00
2740	4471679	CUMPLE	2025-07-07 19:21:00
2741	4821537	CUMPLE	2025-07-07 19:21:00
2742	2837832	NO CUMPLE	2025-07-07 19:21:00
2743	2837833	NO CUMPLE	2025-07-07 19:21:00
2744	2696871	NO CUMPLE	2025-07-07 19:21:00
2745	2696890	NO CUMPLE	2025-07-07 19:21:00
2746	2485007	NO CUMPLE	2025-07-07 19:21:00
2747	4189644	CUMPLE	2025-07-07 19:21:00
2748	4350183	CUMPLE	2025-07-07 19:21:00
2749	4375933	NO CUMPLE	2025-07-07 19:21:00
2750	4563274	CUMPLE	2025-07-07 19:21:00
2751	4563276	CUMPLE	2025-07-07 19:21:00
2752	4563277	CUMPLE	2025-07-07 19:21:00
2753	4909569	NO CUMPLE	2025-07-07 19:21:00
2754	5185632	CUMPLE	2025-07-07 19:21:00
2755	5334137	CUMPLE	2025-07-07 19:21:00
2756	5334138	CUMPLE	2025-07-07 19:21:00
2757	5334140	CUMPLE	2025-07-07 19:21:00
2758	5334141	CUMPLE	2025-07-07 19:21:00
2759	4192898	CUMPLE	2025-07-07 19:21:00
2760	4846277	CUMPLE	2025-07-07 19:21:00
2761	5417507	CUMPLE	2025-07-07 19:21:00
2762	5417508	CUMPLE	2025-07-07 19:21:00
2763	5417509	CUMPLE	2025-07-07 19:21:00
2764	5417510	CUMPLE	2025-07-07 19:21:00
2765	5417511	CUMPLE	2025-07-07 19:21:00
2766	5417577	CUMPLE	2025-07-07 19:21:00
2767	5417578	CUMPLE	2025-07-07 19:21:00
2768	5417579	CUMPLE	2025-07-07 19:21:00
2769	5057384	NO CUMPLE	2025-07-07 19:21:00
2770	5057896	NO CUMPLE	2025-07-07 19:21:00
2771	5414684	NO CUMPLE	2025-07-07 19:21:00
2772	2654203	CUMPLE	2025-07-07 19:21:00
2773	2654205	CUMPLE	2025-07-07 19:21:00
2774	4031949	NO CUMPLE	2025-07-07 19:21:00
2775	4065513	NO CUMPLE	2025-07-07 19:21:00
2776	4065514	NO CUMPLE	2025-07-07 19:21:00
2777	4065515	NO CUMPLE	2025-07-07 19:21:00
2778	4235697	CUMPLE	2025-07-07 19:21:00
2779	4350232	CUMPLE	2025-07-07 19:21:00
2780	4458010	NO CUMPLE	2025-07-07 19:21:00
2781	5056911	NO CUMPLE	2025-07-07 19:21:00
2782	5056912	NO CUMPLE	2025-07-07 19:21:00
2783	5415306	CUMPLE	2025-07-07 19:21:00
2784	2543610	CUMPLE	2025-07-07 19:21:00
2785	4232402	CUMPLE	2025-07-07 19:21:00
2786	4316846	NO CUMPLE	2025-07-07 19:21:00
2787	4757601	CUMPLE	2025-07-07 19:21:00
2788	4757602	CUMPLE	2025-07-07 19:21:00
2789	4757603	CUMPLE	2025-07-07 19:21:00
2790	4757605	CUMPLE	2025-07-07 19:21:00
2791	5450092	CUMPLE	2025-07-07 19:21:00
2792	4774029	CUMPLE	2025-07-07 19:21:00
2793	4774032	CUMPLE	2025-07-07 19:21:00
2794	4774325	CUMPLE	2025-07-07 19:21:00
2795	4774328	CUMPLE	2025-07-07 19:21:00
2796	4774329	CUMPLE	2025-07-07 19:21:00
2797	5187818	CUMPLE	2025-07-07 19:21:00
2798	5426114	CUMPLE	2025-07-07 19:21:00
2799	5426115	CUMPLE	2025-07-07 19:21:00
2800	5511796	CUMPLE	2025-07-07 19:21:00
2801	5274723	NO CUMPLE	2025-07-07 19:21:00
2802	5274724	NO CUMPLE	2025-07-07 19:21:00
2803	4001654	NO CUMPLE	2025-07-07 19:21:00
2804	4001658	NO CUMPLE	2025-07-07 19:21:00
2805	4019532	NO CUMPLE	2025-07-07 19:21:00
2806	1822133	CUMPLE	2025-07-07 19:21:00
2807	2473196	CUMPLE	2025-07-07 19:21:00
2808	2715546	CUMPLE	2025-07-07 19:21:00
2809	5055814	CUMPLE	2025-07-07 19:21:00
2810	4407094	CUMPLE	2025-07-07 19:21:00
2811	4407100	CUMPLE	2025-07-07 19:21:00
2812	5038067	CUMPLE	2025-07-07 19:21:00
2813	5038068	CUMPLE	2025-07-07 19:21:00
2814	5038095	CUMPLE	2025-07-07 19:21:00
2815	5074672	NO CUMPLE	2025-07-07 19:21:00
2816	4871311	NO CUMPLE	2025-07-07 19:21:00
2817	2454972	NO CUMPLE	2025-07-07 19:21:00
2818	2617509	NO CUMPLE	2025-07-07 19:21:00
2819	4569369	CUMPLE	2025-07-07 19:21:00
2820	4569370	CUMPLE	2025-07-07 19:21:00
2821	4819786	NO CUMPLE	2025-07-07 19:21:00
2822	5014818	NO CUMPLE	2025-07-07 19:21:00
2823	2121847	NO CUMPLE	2025-07-07 19:21:00
2824	5086598	CUMPLE	2025-07-07 19:21:00
2825	5086602	CUMPLE	2025-07-07 19:21:00
2826	4904451	CUMPLE	2025-07-07 19:21:00
2827	4904454	CUMPLE	2025-07-07 19:21:00
2828	4904455	CUMPLE	2025-07-07 19:21:00
2829	4904457	CUMPLE	2025-07-07 19:21:00
2830	4025430	CUMPLE	2025-07-07 19:21:00
2831	5094822	NO CUMPLE	2025-07-07 19:21:00
2832	5204935	NO CUMPLE	2025-07-07 19:21:00
2833	5224365	CUMPLE	2025-07-07 19:21:00
2834	4197075	NO CUMPLE	2025-07-07 19:21:00
2835	2732150	CUMPLE	2025-07-07 19:21:00
2836	2884483	NO CUMPLE	2025-07-07 19:21:00
2837	4713649	CUMPLE	2025-07-07 19:21:00
2838	4049608	NO CUMPLE	2025-07-07 19:21:00
2839	4326470	NO CUMPLE	2025-07-07 19:21:00
2840	2658337	NO CUMPLE	2025-07-07 19:21:00
2841	4156630	CUMPLE	2025-07-07 19:21:00
2842	4156631	CUMPLE	2025-07-07 19:21:00
2843	4156633	CUMPLE	2025-07-07 19:21:00
2844	5099779	CUMPLE	2025-07-07 19:21:00
2845	5511795	CUMPLE	2025-07-07 19:21:00
2846	5355501	CUMPLE	2025-07-07 19:21:00
2847	2172050	NO CUMPLE	2025-07-07 19:21:00
2848	2172063	NO CUMPLE	2025-07-07 19:21:00
2849	2172062	NO CUMPLE	2025-07-07 19:21:00
2850	2308152	NO CUMPLE	2025-07-07 19:21:00
2851	2308151	NO CUMPLE	2025-07-07 19:21:00
2852	2308223	NO CUMPLE	2025-07-07 19:21:00
2853	2308222	NO CUMPLE	2025-07-07 19:21:00
2854	2461444	NO CUMPLE	2025-07-07 19:21:00
2855	2461442	NO CUMPLE	2025-07-07 19:21:00
2856	2308221	NO CUMPLE	2025-07-07 19:21:00
2857	2900591	NO CUMPLE	2025-07-07 19:21:00
2858	2577408	NO CUMPLE	2025-07-07 19:21:00
2859	2987104	NO CUMPLE	2025-07-07 19:21:00
2860	5445461	NO CUMPLE	2025-07-07 19:21:00
2861	5245480	NO CUMPLE	2025-07-07 19:21:00
2862	2308150	NO CUMPLE	2025-07-07 19:21:00
2863	2566890	CUMPLE	2025-07-07 19:21:00
2864	4852464	CUMPLE	2025-07-07 19:21:00
2865	2414534	CUMPLE	2025-07-07 19:21:00
2866	2414531	CUMPLE	2025-07-07 19:21:00
2867	4359093	CUMPLE	2025-07-07 19:21:00
2868	4866387	CUMPLE	2025-07-07 19:21:00
2869	4866388	CUMPLE	2025-07-07 19:21:00
2870	4866392	CUMPLE	2025-07-07 19:21:00
2871	4866443	CUMPLE	2025-07-07 19:21:00
2872	5348574	CUMPLE	2025-07-07 19:21:00
2873	5348575	CUMPLE	2025-07-07 19:21:00
2874	5348576	CUMPLE	2025-07-07 19:21:00
2875	5348577	CUMPLE	2025-07-07 19:21:00
2876	5348581	CUMPLE	2025-07-07 19:21:00
2877	5393207	CUMPLE	2025-07-07 19:21:00
2878	5393208	CUMPLE	2025-07-07 19:21:00
2879	5393209	CUMPLE	2025-07-07 19:21:00
2880	5393210	CUMPLE	2025-07-07 19:21:00
2881	5393211	CUMPLE	2025-07-07 19:21:00
2882	5393212	CUMPLE	2025-07-07 19:21:00
2883	5419817	CUMPLE	2025-07-07 19:21:00
2884	5419831	CUMPLE	2025-07-07 19:21:00
2885	5448183	CUMPLE	2025-07-07 19:21:00
2886	4006564	CUMPLE	2025-07-07 19:21:00
2887	2391738	CUMPLE	2025-07-07 19:21:00
2888	2455265	CUMPLE	2025-07-07 19:21:00
2889	5407154	CUMPLE	2025-07-07 19:21:00
2890	4023121	CUMPLE	2025-07-07 19:21:00
2891	4894517	CUMPLE	2025-07-07 19:21:00
2892	4465526	CUMPLE	2025-07-07 19:21:00
2893	4304120	NO CUMPLE	2025-07-07 19:21:00
2894	4563275	CUMPLE	2025-07-07 19:21:00
2895	4921436	CUMPLE	2025-07-07 19:21:00
2896	4278917	CUMPLE	2025-07-07 19:21:00
2897	4560122	NO CUMPLE	2025-07-07 19:21:00
2898	4846272	CUMPLE	2025-07-07 19:21:00
2899	5411280	CUMPLE	2025-07-07 19:21:00
2900	5411302	CUMPLE	2025-07-07 19:21:00
2901	4235694	CUMPLE	2025-07-07 19:21:00
2902	4320611	CUMPLE	2025-07-07 19:21:00
2903	4458014	CUMPLE	2025-07-07 19:21:00
2904	4773299	CUMPLE	2025-07-07 19:21:00
2905	5319786	CUMPLE	2025-07-07 19:21:00
2906	4232401	CUMPLE	2025-07-07 19:21:00
2907	2885359	CUMPLE	2025-07-07 19:21:00
2908	4273715	NO CUMPLE	2025-07-07 19:21:00
2909	4273720	NO CUMPLE	2025-07-07 19:21:00
2910	4001657	NO CUMPLE	2025-07-07 19:21:00
2911	4450036	CUMPLE	2025-07-07 19:21:00
2912	5055815	CUMPLE	2025-07-07 19:21:00
2913	4225125	CUMPLE	2025-07-07 19:21:00
2914	4435995	CUMPLE	2025-07-07 19:21:00
2915	5418031	CUMPLE	2025-07-07 19:21:00
2916	5418035	CUMPLE	2025-07-07 19:21:00
2917	4493141	CUMPLE	2025-07-07 19:21:00
2918	4493142	CUMPLE	2025-07-07 19:21:00
2919	5436358	CUMPLE	2025-07-07 19:21:00
2920	5436359	CUMPLE	2025-07-07 19:21:00
2921	2562324	NO CUMPLE	2025-07-07 19:21:00
2922	4808852	NO CUMPLE	2025-07-07 19:21:00
2923	4808854	NO CUMPLE	2025-07-07 19:21:00
2924	4808855	NO CUMPLE	2025-07-07 19:21:00
2925	4808856	NO CUMPLE	2025-07-07 19:21:00
2926	4808857	NO CUMPLE	2025-07-07 19:21:00
2927	5055369	CUMPLE	2025-07-07 19:21:00
2928	4326472	CUMPLE	2025-07-07 19:21:00
2929	4113548	NO CUMPLE	2025-07-07 19:21:00
2930	2654298	NO CUMPLE	2025-07-07 19:21:00
2931	2654300	CUMPLE	2025-07-07 19:21:00
2932	4976456	NO CUMPLE	2025-07-07 19:21:00
2933	2959112	NO CUMPLE	2025-07-07 19:21:00
2934	4566683	CUMPLE	2025-07-07 19:21:00
2935	4566684	CUMPLE	2025-07-07 19:21:00
2936	4566685	CUMPLE	2025-07-07 19:21:00
2937	4566686	CUMPLE	2025-07-07 19:21:00
2938	4566687	CUMPLE	2025-07-07 19:21:00
2939	5397798	CUMPLE	2025-07-07 19:21:00
2940	5397799	CUMPLE	2025-07-07 19:21:00
2941	5397803	CUMPLE	2025-07-07 19:21:00
2942	2092751	NO CUMPLE	2025-07-07 19:21:00
2943	5397164	CUMPLE	2025-07-07 19:21:00
2944	5397165	CUMPLE	2025-07-07 19:21:00
2945	5397173	CUMPLE	2025-07-07 19:21:00
2946	5397175	CUMPLE	2025-07-07 19:21:00
2947	4324035	NO CUMPLE	2025-07-07 19:21:00
2948	2754063	CUMPLE	2025-07-07 19:21:00
2949	2696880	NO CUMPLE	2025-07-07 19:21:00
2950	4367773	CUMPLE	2025-07-07 19:21:00
2951	4367774	CUMPLE	2025-07-07 19:21:00
2952	4469127	CUMPLE	2025-07-07 19:21:00
2953	4359094	CUMPLE	2025-07-07 19:21:00
2954	4359096	CUMPLE	2025-07-07 19:21:00
2955	4814034	CUMPLE	2025-07-07 19:21:00
2956	4866435	CUMPLE	2025-07-07 19:21:00
2957	5411301	CUMPLE	2025-07-07 19:21:00
2958	5416940	CUMPLE	2025-07-07 19:21:00
2959	5416943	CUMPLE	2025-07-07 19:21:00
2960	4336819	NO CUMPLE	2025-07-07 19:21:00
2961	4866391	CUMPLE	2025-07-07 19:21:00
2962	5437814	CUMPLE	2025-07-07 19:21:00
2963	5447835	CUMPLE	2025-07-07 19:21:00
2964	5448565	CUMPLE	2025-07-07 19:21:00
2965	5039772	CUMPLE	2025-07-07 19:21:00
2966	4744608	CUMPLE	2025-07-07 19:21:00
2967	2500632	NO CUMPLE	2025-07-07 19:21:00
2968	1501563	CUMPLE	2025-07-07 19:21:00
2969	4166448	CUMPLE	2025-07-07 19:21:00
2970	4102216	CUMPLE	2025-07-07 19:21:00
2971	4698800	CUMPLE	2025-07-07 19:21:00
2972	2942432	CUMPLE	2025-07-07 19:21:00
2973	2942433	CUMPLE	2025-07-07 19:21:00
2974	4578342	NO CUMPLE	2025-07-07 19:21:00
2975	4578343	NO CUMPLE	2025-07-07 19:21:00
2976	4578345	NO CUMPLE	2025-07-07 19:21:00
2977	5406441	CUMPLE	2025-07-07 19:21:00
2978	5406443	CUMPLE	2025-07-07 19:21:00
2979	5426401	CUMPLE	2025-07-07 19:21:00
2980	5426404	CUMPLE	2025-07-07 19:21:00
2981	5426406	CUMPLE	2025-07-07 19:21:00
2982	5426408	CUMPLE	2025-07-07 19:21:00
2983	5426410	CUMPLE	2025-07-07 19:21:00
2984	5436356	CUMPLE	2025-07-07 19:21:00
2985	5436357	CUMPLE	2025-07-07 19:21:00
2986	5436360	CUMPLE	2025-07-07 19:21:00
2987	2652752	CUMPLE	2025-07-07 19:21:00
2988	4923829	CUMPLE	2025-07-07 19:21:00
2989	5010382	CUMPLE	2025-07-07 19:21:00
2990	5010383	CUMPLE	2025-07-07 19:21:00
2991	5316367	CUMPLE	2025-07-07 19:21:00
2992	2880513	CUMPLE	2025-07-07 19:21:00
2993	2880515	CUMPLE	2025-07-07 19:21:00
2994	5512552	CUMPLE	2025-07-07 19:21:00
2995	5512553	CUMPLE	2025-07-07 19:21:00
2996	5512555	CUMPLE	2025-07-07 19:21:00
2997	5512556	CUMPLE	2025-07-07 19:21:00
2998	5512557	CUMPLE	2025-07-07 19:21:00
2999	5551858	CUMPLE	2025-07-07 19:21:00
3000	5056913	CUMPLE	2025-07-07 19:21:00
3001	5056987	CUMPLE	2025-07-07 19:21:00
3002	5056991	CUMPLE	2025-07-07 19:21:00
3003	5404443	CUMPLE	2025-07-07 19:21:00
3004	5404444	CUMPLE	2025-07-07 19:21:00
3005	5404445	CUMPLE	2025-07-07 19:21:00
3006	5404446	CUMPLE	2025-07-07 19:21:00
3007	5404447	CUMPLE	2025-07-07 19:21:00
3008	5404448	CUMPLE	2025-07-07 19:21:00
3009	5404620	CUMPLE	2025-07-07 19:21:00
3010	5404621	CUMPLE	2025-07-07 19:21:00
3011	5404623	CUMPLE	2025-07-07 19:21:00
3012	5404625	CUMPLE	2025-07-07 19:21:00
3013	5417687	CUMPLE	2025-07-07 19:21:00
3014	5417688	CUMPLE	2025-07-07 19:21:00
3015	5356606	CUMPLE	2025-07-07 19:21:00
3016	5356607	CUMPLE	2025-07-07 19:21:00
3017	5356608	CUMPLE	2025-07-07 19:21:00
3018	5356609	CUMPLE	2025-07-07 19:21:00
3019	5356610	CUMPLE	2025-07-07 19:21:00
3020	4569769	CUMPLE	2025-07-07 19:21:00
3021	4905571	CUMPLE	2025-07-07 19:21:00
3022	4227116	CUMPLE	2025-07-07 19:21:00
3023	5010445	CUMPLE	2025-07-07 19:21:00
3024	5010446	CUMPLE	2025-07-07 19:21:00
3025	5010447	CUMPLE	2025-07-07 19:21:00
3026	5010448	CUMPLE	2025-07-07 19:21:00
3027	5010449	CUMPLE	2025-07-07 19:21:00
3028	5010450	CUMPLE	2025-07-07 19:21:00
3029	4170014	CUMPLE	2025-07-07 19:21:00
3030	5185633	CUMPLE	2025-07-07 19:21:00
3031	5399769	CUMPLE	2025-07-07 19:21:00
3032	5399770	CUMPLE	2025-07-07 19:21:00
3033	5486179	CUMPLE	2025-07-07 19:21:00
3034	5404606	CUMPLE	2025-07-07 19:21:00
3035	5404607	CUMPLE	2025-07-07 19:21:00
3036	5404608	CUMPLE	2025-07-07 19:21:00
3037	5404610	CUMPLE	2025-07-07 19:21:00
3038	5056760	CUMPLE	2025-07-07 19:21:00
3039	5510949	CUMPLE	2025-07-07 19:21:00
3040	4852447	NO CUMPLE	2025-07-07 19:21:00
3041	4852449	NO CUMPLE	2025-07-07 19:21:00
3042	4438929	CUMPLE	2025-07-07 19:21:00
3043	4438930	CUMPLE	2025-07-07 19:21:00
3044	4702494	CUMPLE	2025-07-07 19:21:00
3045	4702496	CUMPLE	2025-07-07 19:21:00
3046	4883243	CUMPLE	2025-07-07 19:21:00
3047	4883244	CUMPLE	2025-07-07 19:21:00
3048	4883245	CUMPLE	2025-07-07 19:21:00
3049	4883246	CUMPLE	2025-07-07 19:21:00
3050	4883247	CUMPLE	2025-07-07 19:21:00
3051	4926358	CUMPLE	2025-07-07 19:21:00
3052	4926362	CUMPLE	2025-07-07 19:21:00
3053	5085130	CUMPLE	2025-07-07 19:21:00
3054	5085132	CUMPLE	2025-07-07 19:21:00
3055	5085134	CUMPLE	2025-07-07 19:21:00
3056	5164655	CUMPLE	2025-07-07 19:21:00
3057	5164657	CUMPLE	2025-07-07 19:21:00
3058	5164659	CUMPLE	2025-07-07 19:21:00
3059	5164661	CUMPLE	2025-07-07 19:21:00
3060	5164706	CUMPLE	2025-07-07 19:21:00
3061	5164707	CUMPLE	2025-07-07 19:21:00
3062	5164708	CUMPLE	2025-07-07 19:21:00
3063	5164709	CUMPLE	2025-07-07 19:21:00
3064	5280740	CUMPLE	2025-07-07 19:21:00
3065	5280840	CUMPLE	2025-07-07 19:21:00
3066	5280841	CUMPLE	2025-07-07 19:21:00
3067	5280842	CUMPLE	2025-07-07 19:21:00
3068	5393609	CUMPLE	2025-07-07 19:21:00
3069	5416102	CUMPLE	2025-07-07 19:21:00
3070	5416103	CUMPLE	2025-07-07 19:21:00
3071	5416104	CUMPLE	2025-07-07 19:21:00
3072	5416105	CUMPLE	2025-07-07 19:21:00
3073	5417097	CUMPLE	2025-07-07 19:21:00
3074	5417580	CUMPLE	2025-07-07 19:21:00
3075	5417581	CUMPLE	2025-07-07 19:21:00
3076	4997713	CUMPLE	2025-07-07 19:21:00
3077	4714364	CUMPLE	2025-07-07 19:21:00
3078	4714365	CUMPLE	2025-07-07 19:21:00
3079	4524325	CUMPLE	2025-07-07 19:21:00
3080	4524327	CUMPLE	2025-07-07 19:21:00
3081	4524329	CUMPLE	2025-07-07 19:21:00
3082	4524331	CUMPLE	2025-07-07 19:21:00
3083	4573255	CUMPLE	2025-07-07 19:21:00
3084	4573257	CUMPLE	2025-07-07 19:21:00
3085	4975519	CUMPLE	2025-07-07 19:21:00
3086	2780005	CUMPLE	2025-07-07 19:21:00
3087	5043991	CUMPLE	2025-07-07 19:21:00
3088	5043992	CUMPLE	2025-07-07 19:21:00
3089	5043993	CUMPLE	2025-07-07 19:21:00
3090	5043994	CUMPLE	2025-07-07 19:21:00
3091	5273851	CUMPLE	2025-07-07 19:21:00
3092	5273852	CUMPLE	2025-07-07 19:21:00
3093	5273853	CUMPLE	2025-07-07 19:21:00
3094	5164724	CUMPLE	2025-07-07 19:21:00
3095	5264058	CUMPLE	2025-07-07 19:21:00
3096	5264061	CUMPLE	2025-07-07 19:21:00
3097	5351855	CUMPLE	2025-07-07 19:21:00
3098	5450796	CUMPLE	2025-07-07 19:21:00
3099	4229063	CUMPLE	2025-07-07 19:21:00
3100	4050387	CUMPLE	2025-07-07 19:21:00
3101	4591866	CUMPLE	2025-07-07 19:21:00
3102	4747471	CUMPLE	2025-07-07 19:21:00
3103	5397802	CUMPLE	2025-07-07 19:21:00
3104	5057089	NO CUMPLE	2025-07-07 19:21:00
3105	4341736	NO CUMPLE	2025-07-07 19:21:00
3106	4093964	NO CUMPLE	2025-07-07 19:21:00
3107	4093967	NO CUMPLE	2025-07-07 19:21:00
3108	4093968	NO CUMPLE	2025-07-07 19:21:00
3109	2048619	NO CUMPLE	2025-07-07 19:21:00
3110	5379979	CUMPLE	2025-07-07 19:21:00
3111	1347583	CUMPLE	2025-07-07 19:21:00
3112	2454981	CUMPLE	2025-07-07 19:21:00
3113	2454985	CUMPLE	2025-07-07 19:21:00
3114	2942430	CUMPLE	2025-07-07 19:21:00
3115	2600205	CUMPLE	2025-07-07 19:21:00
3116	2616341	NO CUMPLE	2025-07-07 19:21:00
3117	4379006	CUMPLE	2025-07-07 19:21:00
3118	5355880	CUMPLE	2025-07-07 19:21:00
3119	5355881	CUMPLE	2025-07-07 19:21:00
3120	5355885	CUMPLE	2025-07-07 19:21:00
3121	5355886	CUMPLE	2025-07-07 19:21:00
3122	5355887	CUMPLE	2025-07-07 19:21:00
3123	5164547	CUMPLE	2025-07-07 19:21:00
3124	5164548	CUMPLE	2025-07-07 19:21:00
3125	5164728	CUMPLE	2025-07-07 19:21:00
3126	5164730	CUMPLE	2025-07-07 19:21:00
3127	5166128	CUMPLE	2025-07-07 19:21:00
3128	5166129	CUMPLE	2025-07-07 19:21:00
3129	5426972	CUMPLE	2025-07-07 19:21:00
3130	5426976	CUMPLE	2025-07-07 19:21:00
3131	5447702	CUMPLE	2025-07-07 19:21:00
3132	5447703	CUMPLE	2025-07-07 19:21:00
3133	5447704	CUMPLE	2025-07-07 19:21:00
3134	5447705	CUMPLE	2025-07-07 19:21:00
3135	2502399	CUMPLE	2025-07-07 19:21:00
3136	2147281	NO CUMPLE	2025-07-07 19:21:00
3137	4579401	CUMPLE	2025-07-07 19:21:00
3138	2187614	CUMPLE	2025-07-07 19:21:00
3139	4001600	CUMPLE	2025-07-07 19:21:00
3140	2455317	CUMPLE	2025-07-07 19:21:00
3141	4743397	CUMPLE	2025-07-07 19:21:00
3142	2571307	NO CUMPLE	2025-07-07 19:21:00
3143	4293970	NO CUMPLE	2025-07-07 19:21:00
3144	4527357	CUMPLE	2025-07-07 19:21:00
3145	4527358	CUMPLE	2025-07-07 19:21:00
3146	4527572	CUMPLE	2025-07-07 19:21:00
3147	4350182	CUMPLE	2025-07-07 19:21:00
3148	4878769	CUMPLE	2025-07-07 19:21:00
3149	5185631	CUMPLE	2025-07-07 19:21:00
3150	5404332	CUMPLE	2025-07-07 19:21:00
3151	5404333	CUMPLE	2025-07-07 19:21:00
3152	5404336	CUMPLE	2025-07-07 19:21:00
3153	4278918	CUMPLE	2025-07-07 19:21:00
3154	4866449	CUMPLE	2025-07-07 19:21:00
3155	5510454	CUMPLE	2025-07-07 19:21:00
3156	2916394	CUMPLE	2025-07-07 19:21:00
3157	4049128	CUMPLE	2025-07-07 19:21:00
3158	4049130	CUMPLE	2025-07-07 19:21:00
3159	4531960	CUMPLE	2025-07-07 19:21:00
3160	4531961	CUMPLE	2025-07-07 19:21:00
3161	4531964	CUMPLE	2025-07-07 19:21:00
3162	4531965	CUMPLE	2025-07-07 19:21:00
3163	4846345	CUMPLE	2025-07-07 19:21:00
3164	4846346	CUMPLE	2025-07-07 19:21:00
3165	4846347	CUMPLE	2025-07-07 19:21:00
3166	4846348	CUMPLE	2025-07-07 19:21:00
3167	4846349	CUMPLE	2025-07-07 19:21:00
3168	5478986	CUMPLE	2025-07-07 19:21:00
3169	5478989	CUMPLE	2025-07-07 19:21:00
3170	4250692	CUMPLE	2025-07-07 19:21:00
3171	4802212	CUMPLE	2025-07-07 19:21:00
3172	4866347	CUMPLE	2025-07-07 19:21:00
3173	5187601	CUMPLE	2025-07-07 19:21:00
3174	5187602	CUMPLE	2025-07-07 19:21:00
3175	5332859	CUMPLE	2025-07-07 19:21:00
3176	4631214	CUMPLE	2025-07-07 19:21:00
3177	5399484	CUMPLE	2025-07-07 19:21:00
3178	5399487	CUMPLE	2025-07-07 19:21:00
3179	2959082	CUMPLE	2025-07-07 19:21:00
3180	5450100	CUMPLE	2025-07-07 19:21:00
3181	5174626	CUMPLE	2025-07-07 19:21:00
3182	5174628	CUMPLE	2025-07-07 19:21:00
3183	5174630	CUMPLE	2025-07-07 19:21:00
3184	4846304	CUMPLE	2025-07-07 19:21:00
3185	4846305	CUMPLE	2025-07-07 19:21:00
3186	4846306	CUMPLE	2025-07-07 19:21:00
3187	4846307	CUMPLE	2025-07-07 19:21:00
3188	4846308	CUMPLE	2025-07-07 19:21:00
3189	4327962	CUMPLE	2025-07-07 19:21:00
3190	4797663	CUMPLE	2025-07-07 19:21:00
3191	5224342	CUMPLE	2025-07-07 19:21:00
3192	4814185	CUMPLE	2025-07-07 19:21:00
3193	5391771	CUMPLE	2025-07-07 19:21:00
3194	2578772	CUMPLE	2025-07-07 19:21:00
3195	5395712	CUMPLE	2025-07-07 19:21:00
3196	4294533	CUMPLE	2025-07-07 19:21:00
3197	2890862	CUMPLE	2025-07-07 19:21:00
3198	2731158	CUMPLE	2025-07-07 19:21:00
3199	2735543	CUMPLE	2025-07-07 19:21:00
3200	2982984	CUMPLE	2025-07-07 19:21:00
3201	2982985	CUMPLE	2025-07-07 19:21:00
3202	4573262	CUMPLE	2025-07-07 19:21:00
3203	4712465	CUMPLE	2025-07-07 19:21:00
3204	5316906	CUMPLE	2025-07-07 19:21:00
3205	4480792	CUMPLE	2025-07-07 19:21:00
3206	2342113	NO CUMPLE	2025-07-07 19:21:00
3207	2342116	NO CUMPLE	2025-07-07 19:21:00
3208	1779032	CUMPLE	2025-07-07 19:21:00
3209	2764317	CUMPLE	2025-07-07 19:21:00
3210	4127863	CUMPLE	2025-07-07 19:21:00
3211	4127864	CUMPLE	2025-07-07 19:21:00
3212	4127865	CUMPLE	2025-07-07 19:21:00
3213	4127866	CUMPLE	2025-07-07 19:21:00
3214	4154272	CUMPLE	2025-07-07 19:21:00
3215	4271703	CUMPLE	2025-07-07 19:21:00
3216	4350184	CUMPLE	2025-07-07 19:21:00
3217	4879844	CUMPLE	2025-07-07 19:21:00
3218	4925258	CUMPLE	2025-07-07 19:21:00
3219	4925259	CUMPLE	2025-07-07 19:21:00
3220	5164449	CUMPLE	2025-07-07 19:21:00
3221	5355916	CUMPLE	2025-07-07 19:21:00
3222	5355917	CUMPLE	2025-07-07 19:21:00
3223	5355921	CUMPLE	2025-07-07 19:21:00
3224	5355922	CUMPLE	2025-07-07 19:21:00
3225	5355923	CUMPLE	2025-07-07 19:21:00
3226	2910305	CUMPLE	2025-07-07 19:21:00
3227	2910308	CUMPLE	2025-07-07 19:21:00
3228	4454533	CUMPLE	2025-07-07 19:21:00
3229	4454534	CUMPLE	2025-07-07 19:21:00
3230	5164545	CUMPLE	2025-07-07 19:21:00
3231	5164546	CUMPLE	2025-07-07 19:21:00
3232	5164568	CUMPLE	2025-07-07 19:21:00
3233	5057510	CUMPLE	2025-07-07 19:21:00
3234	4235695	CUMPLE	2025-07-07 19:21:00
3235	4350231	CUMPLE	2025-07-07 19:21:00
3236	4350237	CUMPLE	2025-07-07 19:21:00
3237	4789466	CUMPLE	2025-07-07 19:21:00
3238	4250690	NO CUMPLE	2025-07-07 19:21:00
3239	4467340	NO CUMPLE	2025-07-07 19:21:00
3240	4467404	NO CUMPLE	2025-07-07 19:21:00
3241	4565780	NO CUMPLE	2025-07-07 19:21:00
3242	4565781	NO CUMPLE	2025-07-07 19:21:00
3243	4565782	NO CUMPLE	2025-07-07 19:21:00
3244	4565783	NO CUMPLE	2025-07-07 19:21:00
3245	4565784	NO CUMPLE	2025-07-07 19:21:00
3246	4565785	NO CUMPLE	2025-07-07 19:21:00
3247	2977217	CUMPLE	2025-07-07 19:21:00
3248	2977218	CUMPLE	2025-07-07 19:21:00
3249	2977219	CUMPLE	2025-07-07 19:21:00
3250	2977221	CUMPLE	2025-07-07 19:21:00
3251	5426118	CUMPLE	2025-07-07 19:21:00
3252	5426828	CUMPLE	2025-07-07 19:21:00
3253	5447634	CUMPLE	2025-07-07 19:21:00
3254	5447637	CUMPLE	2025-07-07 19:21:00
3255	4050052	CUMPLE	2025-07-07 19:21:00
3256	4050057	CUMPLE	2025-07-07 19:21:00
3257	4450051	CUMPLE	2025-07-07 19:21:00
3258	5392918	NO CUMPLE	2025-07-07 19:21:00
3259	2473195	NO CUMPLE	2025-07-07 19:21:00
3260	2473199	NO CUMPLE	2025-07-07 19:21:00
3261	4451182	NO CUMPLE	2025-07-07 19:21:00
3262	2960898	CUMPLE	2025-07-07 19:21:00
3263	5185641	CUMPLE	2025-07-07 19:21:00
3264	4514004	CUMPLE	2025-07-07 19:21:00
3265	4789499	NO CUMPLE	2025-07-07 19:21:00
3266	5185206	NO CUMPLE	2025-07-07 19:21:00
3267	2454976	NO CUMPLE	2025-07-07 19:21:00
3268	2454982	NO CUMPLE	2025-07-07 19:21:00
3269	4573263	CUMPLE	2025-07-07 19:21:00
3270	2342114	NO CUMPLE	2025-07-07 19:21:00
3271	2342115	NO CUMPLE	2025-07-07 19:21:00
3272	5436338	CUMPLE	2025-07-07 19:21:00
3273	5436343	CUMPLE	2025-07-07 19:21:00
3274	2696840	NO CUMPLE	2025-07-07 19:21:00
3275	2696841	NO CUMPLE	2025-07-07 19:21:00
3276	4693468	CUMPLE	2025-07-07 19:21:00
3277	4995153	NO CUMPLE	2025-07-07 19:21:00
3278	4995764	CUMPLE	2025-07-07 19:21:00
3279	4995765	CUMPLE	2025-07-07 19:21:00
3280	4995767	CUMPLE	2025-07-07 19:21:00
3281	5013795	NO CUMPLE	2025-07-07 19:21:00
3282	5013796	NO CUMPLE	2025-07-07 19:21:00
3283	5013797	NO CUMPLE	2025-07-07 19:21:00
3284	4702492	CUMPLE	2025-07-07 19:21:00
3285	4702495	CUMPLE	2025-07-07 19:21:00
3286	4438192	CUMPLE	2025-07-07 19:21:00
3287	4589865	CUMPLE	2025-07-07 19:21:00
3288	4589866	CUMPLE	2025-07-07 19:21:00
3289	5164544	CUMPLE	2025-07-07 19:21:00
3290	5164570	CUMPLE	2025-07-07 19:21:00
3291	5324564	NO CUMPLE	2025-07-07 19:21:00
3292	5324565	NO CUMPLE	2025-07-07 19:21:00
3293	5334357	NO CUMPLE	2025-07-07 19:21:00
3294	5334377	NO CUMPLE	2025-07-07 19:21:00
3295	5334925	NO CUMPLE	2025-07-07 19:21:00
3296	5426973	NO CUMPLE	2025-07-07 19:21:00
3297	5426974	NO CUMPLE	2025-07-07 19:21:00
3298	5426975	NO CUMPLE	2025-07-07 19:21:00
3299	4844364	NO CUMPLE	2025-07-07 19:21:00
3300	4844366	NO CUMPLE	2025-07-07 19:21:00
3301	4844367	NO CUMPLE	2025-07-07 19:21:00
3302	4897185	NO CUMPLE	2025-07-07 19:21:00
3303	2669359	NO CUMPLE	2025-07-07 19:21:00
3304	5145109	CUMPLE	2025-07-07 19:21:00
3305	5145119	CUMPLE	2025-07-07 19:21:00
3306	5193991	NO CUMPLE	2025-07-07 19:21:00
3307	4394469	CUMPLE	2025-07-07 19:21:00
3308	2536145	CUMPLE	2025-07-07 19:21:00
3309	2536149	CUMPLE	2025-07-07 19:21:00
3310	4297494	CUMPLE	2025-07-07 19:21:00
3311	4297495	CUMPLE	2025-07-07 19:21:00
3312	4297496	CUMPLE	2025-07-07 19:21:00
3313	4297497	CUMPLE	2025-07-07 19:21:00
3314	4297498	CUMPLE	2025-07-07 19:21:00
3315	2731164	CUMPLE	2025-07-07 19:21:00
3316	5413287	CUMPLE	2025-07-07 19:21:00
3317	5413288	CUMPLE	2025-07-07 19:21:00
3318	2981225	NO CUMPLE	2025-07-07 19:21:00
3319	4454100	NO CUMPLE	2025-07-07 19:21:00
3320	2727060	NO CUMPLE	2025-07-07 19:21:00
3321	2727061	NO CUMPLE	2025-07-07 19:21:00
3322	2727062	NO CUMPLE	2025-07-07 19:21:00
3323	2727065	NO CUMPLE	2025-07-07 19:21:00
3324	2727066	NO CUMPLE	2025-07-07 19:21:00
3325	4898246	CUMPLE	2025-07-07 19:21:00
3326	4479829	NO CUMPLE	2025-07-07 19:21:00
3327	4479833	NO CUMPLE	2025-07-07 19:21:00
3328	5524908	NO CUMPLE	2025-07-07 19:21:00
3329	4925548	CUMPLE	2025-07-07 19:21:00
3330	4925549	CUMPLE	2025-07-07 19:21:00
3331	4925552	CUMPLE	2025-07-07 19:21:00
3332	4925553	CUMPLE	2025-07-07 19:21:00
3333	4713675	CUMPLE	2025-07-07 19:21:00
3334	4713676	CUMPLE	2025-07-07 19:21:00
3335	4713677	CUMPLE	2025-07-07 19:21:00
3336	4713678	CUMPLE	2025-07-07 19:21:00
3337	4713679	CUMPLE	2025-07-07 19:21:00
3338	4879845	CUMPLE	2025-07-07 19:21:00
3339	5076519	CUMPLE	2025-07-07 19:21:00
3340	5076520	CUMPLE	2025-07-07 19:21:00
3341	5076521	NO CUMPLE	2025-07-07 19:21:00
3342	5330860	CUMPLE	2025-07-07 19:21:00
3343	5256075	CUMPLE	2025-07-07 19:21:00
3344	4846296	NO CUMPLE	2025-07-07 19:21:00
3345	4846297	NO CUMPLE	2025-07-07 19:21:00
3346	4846298	NO CUMPLE	2025-07-07 19:21:00
3347	4846301	NO CUMPLE	2025-07-07 19:21:00
3348	5177883	NO CUMPLE	2025-07-07 19:21:00
3349	5177884	NO CUMPLE	2025-07-07 19:21:00
3350	5203800	CUMPLE	2025-07-07 19:21:00
3351	5203801	CUMPLE	2025-07-07 19:21:00
3352	5203802	CUMPLE	2025-07-07 19:21:00
3353	5203804	CUMPLE	2025-07-07 19:21:00
3354	5264057	CUMPLE	2025-07-07 19:21:00
3355	5264059	CUMPLE	2025-07-07 19:21:00
3356	5264078	CUMPLE	2025-07-07 19:21:00
3357	5264079	CUMPLE	2025-07-07 19:21:00
3358	2975356	CUMPLE	2025-07-07 19:21:00
3359	4792563	NO CUMPLE	2025-07-07 19:21:00
3360	4792564	NO CUMPLE	2025-07-07 19:21:00
3361	4792566	CUMPLE	2025-07-07 19:21:00
3362	4792567	CUMPLE	2025-07-07 19:21:00
3363	5057233	CUMPLE	2025-07-07 19:21:00
3364	5057234	CUMPLE	2025-07-07 19:21:00
3365	5057235	CUMPLE	2025-07-07 19:21:00
3366	5057236	CUMPLE	2025-07-07 19:21:00
3367	5057237	CUMPLE	2025-07-07 19:21:00
3368	5414679	NO CUMPLE	2025-07-07 19:21:00
3369	5414680	NO CUMPLE	2025-07-07 19:21:00
3370	5414681	NO CUMPLE	2025-07-07 19:21:00
3371	5414682	NO CUMPLE	2025-07-07 19:21:00
3372	5447000	NO CUMPLE	2025-07-07 19:21:00
3373	4062663	CUMPLE	2025-07-07 19:21:00
3374	4062665	CUMPLE	2025-07-07 19:21:00
3375	4312659	CUMPLE	2025-07-07 19:21:00
3376	4312662	NO CUMPLE	2025-07-07 19:21:00
3377	4312664	CUMPLE	2025-07-07 19:21:00
3378	4323877	NO CUMPLE	2025-07-07 19:21:00
3379	4789538	NO CUMPLE	2025-07-07 19:21:00
3380	4789539	NO CUMPLE	2025-07-07 19:21:00
3381	4897191	CUMPLE	2025-07-07 19:21:00
3382	4897193	CUMPLE	2025-07-07 19:21:00
3383	4897194	CUMPLE	2025-07-07 19:21:00
3384	4897195	CUMPLE	2025-07-07 19:21:00
3385	4897209	CUMPLE	2025-07-07 19:21:00
3386	4897760	NO CUMPLE	2025-07-07 19:21:00
3387	4897762	NO CUMPLE	2025-07-07 19:21:00
3388	4897763	NO CUMPLE	2025-07-07 19:21:00
3389	4897765	NO CUMPLE	2025-07-07 19:21:00
3390	4897767	CUMPLE	2025-07-07 19:21:00
3391	5056974	NO CUMPLE	2025-07-07 19:21:00
3392	5056976	CUMPLE	2025-07-07 19:21:00
3393	5063920	NO CUMPLE	2025-07-07 19:21:00
3394	5063922	NO CUMPLE	2025-07-07 19:21:00
3395	5066498	NO CUMPLE	2025-07-07 19:21:00
3396	5066502	NO CUMPLE	2025-07-07 19:21:00
3397	5203896	CUMPLE	2025-07-07 19:21:00
3398	5203897	CUMPLE	2025-07-07 19:21:00
3399	5203898	CUMPLE	2025-07-07 19:21:00
3400	5203899	CUMPLE	2025-07-07 19:21:00
3401	5203900	CUMPLE	2025-07-07 19:21:00
3402	5203901	CUMPLE	2025-07-07 19:21:00
3403	5449271	CUMPLE	2025-07-07 19:21:00
3404	5449272	CUMPLE	2025-07-07 19:21:00
3405	5449273	CUMPLE	2025-07-07 19:21:00
3406	5449274	CUMPLE	2025-07-07 19:21:00
3407	4434399	CUMPLE	2025-07-07 19:21:00
3408	4434401	CUMPLE	2025-07-07 19:21:00
3409	4434402	CUMPLE	2025-07-07 19:21:00
3410	4834573	CUMPLE	2025-07-07 19:21:00
3411	4834574	CUMPLE	2025-07-07 19:21:00
3412	4834575	CUMPLE	2025-07-07 19:21:00
3413	4834576	CUMPLE	2025-07-07 19:21:00
3414	4834577	CUMPLE	2025-07-07 19:21:00
3415	4361147	CUMPLE	2025-07-07 19:21:00
3817	4502994	\N	2025-07-07 17:29:13.628006
3818	4682061	\N	2025-07-07 17:29:21.947573
3819	4516786	\N	2025-07-07 17:29:21.950827
3820	4391767	\N	2025-07-07 17:29:21.957671
3821	5155482	\N	2025-07-07 17:29:21.969404
3822	5155485	\N	2025-07-07 17:29:21.972922
3823	2901492	\N	2025-07-07 17:29:21.979692
3824	4275501	\N	2025-07-07 17:29:21.98118
3825	4343613	\N	2025-07-07 17:29:21.982606
3826	4343617	\N	2025-07-07 17:29:21.983812
3827	2695717	\N	2025-07-07 17:29:21.98682
3828	4325058	\N	2025-07-07 17:29:21.987713
3829	4657143	\N	2025-07-07 17:29:21.989321
3830	2698916	\N	2025-07-07 17:29:21.99137
3831	4926921	\N	2025-07-07 17:29:21.993152
3832	5413380	\N	2025-07-07 17:29:22.000992
3833	5553098	\N	2025-07-07 17:29:22.006403
3834	4561646	\N	2025-07-07 17:29:22.014273
3835	5204936	\N	2025-07-07 17:29:22.01689
3836	4135366	\N	2025-07-07 17:29:22.028469
3837	2395291	\N	2025-07-07 17:29:22.032147
3838	4327544	\N	2025-07-07 17:29:22.037753
3839	2582133	\N	2025-07-07 17:29:22.049316
3840	5466095	\N	2025-07-07 17:29:22.05079
3841	4489560	\N	2025-07-07 17:29:22.06071
3842	5365259	\N	2025-07-07 17:29:22.063943
3843	5195549	\N	2025-07-07 17:29:22.064956
3844	2392715	\N	2025-07-07 17:29:22.075287
3845	5294201	\N	2025-07-07 17:29:22.079543
3846	5055379	\N	2025-07-07 17:29:22.086191
3847	4006198	\N	2025-07-07 17:29:22.087707
3848	4521014	\N	2025-07-07 17:29:22.088991
3849	4309445	\N	2025-07-07 17:29:22.093699
3850	4449798	\N	2025-07-07 17:29:22.097752
3851	4809505	\N	2025-07-07 17:29:22.098811
3852	4850058	\N	2025-07-07 17:29:22.099386
3853	4047194	\N	2025-07-07 17:29:22.100376
3854	2648460	\N	2025-07-07 17:29:22.102919
3855	4300151	\N	2025-07-07 17:29:22.106404
3856	4873997	\N	2025-07-07 17:29:22.107433
3857	1359527	\N	2025-07-07 17:29:22.108057
3858	2406881	\N	2025-07-07 17:29:22.108618
3859	2546105	\N	2025-07-07 17:29:22.10917
3860	5450403	\N	2025-07-07 17:29:22.112638
3861	2895791	\N	2025-07-07 17:29:22.113772
3862	4004226	\N	2025-07-07 17:29:22.117904
3863	4934598	\N	2025-07-07 17:29:22.119139
3864	5085127	\N	2025-07-07 17:29:22.120339
3865	2126336	\N	2025-07-07 17:29:22.12648
3866	4559614	\N	2025-07-07 17:29:22.127723
3867	4045454	\N	2025-07-07 17:29:22.13116
3868	2385962	\N	2025-07-07 17:29:22.132849
3869	5365285	\N	2025-07-07 17:29:22.133459
3870	5166654	\N	2025-07-07 17:29:22.134048
3871	4392881	\N	2025-07-07 17:29:22.134615
3872	4392883	\N	2025-07-07 17:29:22.135221
3873	4392884	\N	2025-07-07 17:29:22.135785
3874	5281038	\N	2025-07-07 17:29:22.137158
3875	4716800	\N	2025-07-07 17:29:22.137722
3876	2387701	\N	2025-07-07 17:29:22.139691
3877	4302517	\N	2025-07-07 17:29:22.140933
3878	4527328	\N	2025-07-07 17:29:22.142415
3879	4527595	\N	2025-07-07 17:29:22.143757
3880	2958590	\N	2025-07-07 17:29:22.144777
3881	2958593	\N	2025-07-07 17:29:22.145763
3882	2958595	\N	2025-07-07 17:29:22.146345
3883	4485871	\N	2025-07-07 17:29:22.147311
3884	5513398	\N	2025-07-07 17:29:22.147884
3885	5513399	\N	2025-07-07 17:29:22.148653
3886	5513400	\N	2025-07-07 17:29:22.148923
3887	5379594	\N	2025-07-07 17:29:22.149295
3888	5057091	\N	2025-07-07 17:29:22.150678
3889	5086604	\N	2025-07-07 17:29:22.151841
3890	5155556	\N	2025-07-07 17:29:22.152273
3891	5155559	\N	2025-07-07 17:29:22.152687
3892	4883450	\N	2025-07-07 17:29:22.153073
3893	4883451	\N	2025-07-07 17:29:22.153779
3894	4883454	\N	2025-07-07 17:29:22.154038
3895	5424649	\N	2025-07-07 17:29:22.154421
3896	4883448	\N	2025-07-07 17:29:22.154795
3897	4883452	\N	2025-07-07 17:29:22.155915
3898	5057509	\N	2025-07-07 17:29:22.1566
3899	4518427	\N	2025-07-07 17:29:22.157521
3900	5398263	\N	2025-07-07 17:29:22.158666
3901	2562082	\N	2025-07-07 17:29:22.158968
3902	4336813	\N	2025-07-07 17:29:22.159763
3903	4866365	\N	2025-07-07 17:29:22.160329
3904	4866368	\N	2025-07-07 17:29:22.16107
3905	5001557	\N	2025-07-07 17:29:22.161516
3906	5044110	\N	2025-07-07 17:29:22.161916
3907	5044112	\N	2025-07-07 17:29:22.162298
3908	5324966	\N	2025-07-07 17:29:22.162676
3909	1779031	\N	2025-07-07 17:29:22.163055
3910	2423157	\N	2025-07-07 17:29:22.163767
3911	2600207	\N	2025-07-07 17:29:22.164021
3912	2879878	\N	2025-07-07 17:29:22.164571
3913	2957480	\N	2025-07-07 17:29:22.164936
3914	4287748	\N	2025-07-07 17:29:22.165526
3915	4324846	\N	2025-07-07 17:29:22.166036
3916	4324848	\N	2025-07-07 17:29:22.166859
3917	4376138	\N	2025-07-07 17:29:22.167255
3918	4472694	\N	2025-07-07 17:29:22.167636
3919	4472695	\N	2025-07-07 17:29:22.168006
3920	4472696	\N	2025-07-07 17:29:22.168375
3921	4472697	\N	2025-07-07 17:29:22.168752
3922	4550993	\N	2025-07-07 17:29:22.169384
3923	5513951	\N	2025-07-07 17:29:22.169852
3924	5556155	\N	2025-07-07 17:29:22.170235
3925	5556156	\N	2025-07-07 17:29:22.1708
3926	5556157	\N	2025-07-07 17:29:22.171478
3927	5556159	\N	2025-07-07 17:29:22.172217
3928	5556162	\N	2025-07-07 17:29:22.172728
3929	1302393	\N	2025-07-07 17:29:22.173288
3930	2423158	\N	2025-07-07 17:29:22.174732
3931	2600206	\N	2025-07-07 17:29:22.175495
3932	4047978	\N	2025-07-07 17:29:22.176123
3933	4286227	\N	2025-07-07 17:29:22.176988
3934	4324847	\N	2025-07-07 17:29:22.177589
3935	4472692	\N	2025-07-07 17:29:22.178741
3936	4579024	\N	2025-07-07 17:29:22.179596
3937	4592155	\N	2025-07-07 17:29:22.181588
3938	4823540	\N	2025-07-07 17:29:22.18221
3939	4898333	\N	2025-07-07 17:29:22.182808
3940	577324	\N	2025-07-07 17:29:22.183654
3941	2919471	\N	2025-07-07 17:29:22.185492
3942	4875560	\N	2025-07-07 17:29:22.18659
3943	1779030	\N	2025-07-07 17:29:22.187011
3944	2600302	\N	2025-07-07 17:29:22.188442
3945	4271174	\N	2025-07-07 17:29:22.189724
3946	4438926	\N	2025-07-07 17:29:22.190326
3947	4438928	\N	2025-07-07 17:29:22.191982
3948	4512734	\N	2025-07-07 17:29:22.19248
3949	4898517	\N	2025-07-07 17:29:22.194073
3950	5356614	\N	2025-07-07 17:29:22.19536
3951	572311	\N	2025-07-07 17:29:22.195866
3952	4327322	\N	2025-07-07 17:29:22.197816
3953	617665	\N	2025-07-07 17:29:22.198819
3954	4716799	\N	2025-07-07 17:29:22.20021
3955	4273393	\N	2025-07-07 17:29:22.201814
3956	2577137	\N	2025-07-07 17:29:22.20447
3957	2886229	\N	2025-07-07 17:29:22.205799
3958	38681	\N	2025-07-07 17:29:22.206147
3959	4016836	\N	2025-07-07 17:29:22.2066
3960	5394308	\N	2025-07-07 17:29:22.207006
3961	5394309	\N	2025-07-07 17:29:22.207918
3962	569370	\N	2025-07-07 17:29:22.208291
3963	5255817	\N	2025-07-07 17:29:22.208655
3964	5417336	\N	2025-07-07 17:29:22.209639
3965	5417337	\N	2025-07-07 17:29:22.210169
3966	5214307	\N	2025-07-07 17:29:22.216105
3967	2956339	\N	2025-07-07 17:29:22.21764
3968	2956341	\N	2025-07-07 17:29:22.218112
3969	2959350	\N	2025-07-07 17:29:22.218494
3970	4757506	\N	2025-07-07 17:29:22.218869
3971	5044111	\N	2025-07-07 17:29:22.219231
3972	5424650	\N	2025-07-07 17:29:22.220458
3973	5424657	\N	2025-07-07 17:29:22.222291
3974	5424658	\N	2025-07-07 17:29:22.222833
3975	4250066	\N	2025-07-07 17:29:22.225482
3976	4336814	\N	2025-07-07 17:29:22.226133
3977	4469344	\N	2025-07-07 17:29:22.22653
3978	4499062	\N	2025-07-07 17:29:22.226923
3979	4777193	\N	2025-07-07 17:29:22.227297
3980	5039475	\N	2025-07-07 17:29:22.227667
3981	5424646	\N	2025-07-07 17:29:22.228366
3982	5424659	\N	2025-07-07 17:29:22.229294
3983	4745030	\N	2025-07-07 17:29:22.230494
3984	5244365	\N	2025-07-07 17:29:22.23357
3985	5395590	\N	2025-07-07 17:29:22.235211
3986	5225119	\N	2025-07-07 17:29:22.236812
3987	4278919	\N	2025-07-07 17:29:22.239445
3988	5518191	\N	2025-07-07 17:29:22.244814
3989	5518193	\N	2025-07-07 17:29:22.245144
3990	2695726	\N	2025-07-07 17:29:22.246572
3991	5447017	\N	2025-07-07 17:29:22.24717
3992	2695721	\N	2025-07-07 17:29:22.248563
3993	4986390	\N	2025-07-07 17:29:22.252015
3994	2423159	\N	2025-07-07 17:29:22.257222
3995	2617517	\N	2025-07-07 17:29:22.257839
3996	2695725	\N	2025-07-07 17:29:22.258327
3997	2695728	\N	2025-07-07 17:29:22.258936
3998	2717075	\N	2025-07-07 17:29:22.259341
3999	2717076	\N	2025-07-07 17:29:22.259726
4000	2717078	\N	2025-07-07 17:29:22.26014
4001	2756831	\N	2025-07-07 17:29:22.260514
4002	2756834	\N	2025-07-07 17:29:22.261074
4003	2756835	\N	2025-07-07 17:29:22.26159
4004	2756840	\N	2025-07-07 17:29:22.261999
4005	2968956	\N	2025-07-07 17:29:22.262382
4006	4020210	\N	2025-07-07 17:29:22.262759
4007	4020213	\N	2025-07-07 17:29:22.263177
4008	4278585	\N	2025-07-07 17:29:22.26357
4009	4278586	\N	2025-07-07 17:29:22.263946
4010	4278587	\N	2025-07-07 17:29:22.264314
4011	4278588	\N	2025-07-07 17:29:22.264684
4012	4278589	\N	2025-07-07 17:29:22.26505
4013	4297513	\N	2025-07-07 17:29:22.265624
4014	4313872	\N	2025-07-07 17:29:22.26612
4015	4317688	\N	2025-07-07 17:29:22.266573
4016	4471985	\N	2025-07-07 17:29:22.266971
4017	4471986	\N	2025-07-07 17:29:22.268121
4018	4471988	\N	2025-07-07 17:29:22.26856
4019	4472344	\N	2025-07-07 17:29:22.268964
4020	4521362	\N	2025-07-07 17:29:22.269452
4021	4521363	\N	2025-07-07 17:29:22.269888
4022	4521367	\N	2025-07-07 17:29:22.270314
4023	4521483	\N	2025-07-07 17:29:22.270942
4024	4567466	\N	2025-07-07 17:29:22.271397
4025	4578158	\N	2025-07-07 17:29:22.272114
4026	4579477	\N	2025-07-07 17:29:22.272678
4027	792815	\N	2025-07-07 17:29:22.273315
4028	2982982	\N	2025-07-07 17:29:22.274528
4029	5205811	\N	2025-07-07 17:29:22.276105
4030	4801854	\N	2025-07-07 17:29:22.277095
4031	2004039	\N	2025-07-07 17:29:22.277592
4032	2735540	\N	2025-07-07 17:29:22.27846
4033	5280773	\N	2025-07-07 17:29:22.27872
4034	5405305	\N	2025-07-07 17:29:22.279099
4035	4333014	\N	2025-07-07 17:29:22.280043
4036	2977498	\N	2025-07-07 17:29:22.28089
4037	2908150	\N	2025-07-07 17:29:22.2817
4038	4460155	\N	2025-07-07 17:29:22.283514
4039	4465081	\N	2025-07-07 17:29:22.284487
4040	4789500	\N	2025-07-07 17:29:22.28516
4041	5528653	\N	2025-07-07 17:29:22.2917
4042	4388377	\N	2025-07-07 17:29:22.292299
4043	5450051	\N	2025-07-07 17:29:22.292879
4044	5154692	\N	2025-07-07 17:29:22.293601
4045	2562462	\N	2025-07-07 17:29:22.294212
4046	2989773	\N	2025-07-07 17:29:22.294814
4047	4489984	\N	2025-07-07 17:29:22.295393
4048	4577834	\N	2025-07-07 17:29:22.295966
4049	5383036	\N	2025-07-07 17:29:22.296918
4050	4565003	\N	2025-07-07 17:29:22.298088
4051	4322066	\N	2025-07-07 17:29:22.299943
4052	2484969	\N	2025-07-07 17:29:22.30024
4053	4598660	\N	2025-07-07 17:29:22.30203
4054	5205873	\N	2025-07-07 17:29:22.302524
4055	5205874	\N	2025-07-07 17:29:22.303107
4056	5205875	\N	2025-07-07 17:29:22.303492
4057	5205876	\N	2025-07-07 17:29:22.303867
4058	5416032	\N	2025-07-07 17:29:22.30426
4059	2543603	\N	2025-07-07 17:29:22.304631
4060	4271804	\N	2025-07-07 17:29:22.306259
4061	4570094	\N	2025-07-07 17:29:22.307998
4062	4287749	\N	2025-07-07 17:29:22.308753
4063	4570097	\N	2025-07-07 17:29:22.309459
4064	2515018	\N	2025-07-07 17:29:22.30975
4065	4143904	\N	2025-07-07 17:29:22.31068
4066	4143918	\N	2025-07-07 17:29:22.311141
4067	4603863	\N	2025-07-07 17:29:22.3116
4068	4898558	\N	2025-07-07 17:29:22.312004
4069	2016228	\N	2025-07-07 17:29:22.312385
4070	1463433	\N	2025-07-07 17:29:22.313958
4071	1485111	\N	2025-07-07 17:29:22.315098
4072	4364844	\N	2025-07-07 17:29:22.315536
4073	5157725	\N	2025-07-07 17:29:22.316267
4074	146816	\N	2025-07-07 17:29:22.317973
4075	4712469	\N	2025-07-07 17:29:22.318924
4076	70612	\N	2025-07-07 17:29:22.319931
4077	2883526	\N	2025-07-07 17:29:22.323276
4078	4290366	\N	2025-07-07 17:29:22.327461
4079	2956340	\N	2025-07-07 17:29:22.328074
4080	2614251	\N	2025-07-07 17:29:22.329561
4081	4357528	\N	2025-07-07 17:29:22.332136
4082	4468871	\N	2025-07-07 17:29:22.334323
4083	4468873	\N	2025-07-07 17:29:22.33667
4084	4512735	\N	2025-07-07 17:29:22.341576
4085	38690	\N	2025-07-07 17:29:22.344726
4086	2957211	\N	2025-07-07 17:29:22.345659
4087	2013598	\N	2025-07-07 17:29:22.346327
4088	2900833	\N	2025-07-07 17:29:22.346925
4089	4074459	\N	2025-07-07 17:29:22.347963
4090	2342572	\N	2025-07-07 17:29:22.35173
4091	4398769	\N	2025-07-07 17:29:22.352408
4092	2224271	\N	2025-07-07 17:29:22.353006
4093	4229536	\N	2025-07-07 17:29:22.354042
4094	4482733	\N	2025-07-07 17:29:22.359924
4095	4310322	\N	2025-07-07 17:29:22.366395
4096	5145321	\N	2025-07-07 17:29:22.367363
4097	2710899	\N	2025-07-07 17:29:22.375536
4098	2777039	\N	2025-07-07 17:29:22.376518
4099	4502107	\N	2025-07-07 17:29:22.378384
4100	2379503	\N	2025-07-07 17:29:22.383556
4101	2710878	\N	2025-07-07 17:29:22.384535
4102	5103247	\N	2025-07-07 17:29:22.385105
4103	797053	\N	2025-07-07 17:29:22.38687
4104	5355119	\N	2025-07-07 17:29:22.387666
4105	4334480	\N	2025-07-07 17:29:22.39009
4106	4566689	\N	2025-07-07 17:29:22.391505
4107	4566693	\N	2025-07-07 17:29:22.393544
4108	4237779	\N	2025-07-07 17:29:22.399347
4109	4237780	\N	2025-07-07 17:29:22.400256
4110	4934023	\N	2025-07-07 17:29:22.402596
4111	4493143	\N	2025-07-07 17:29:22.404062
4112	2540277	\N	2025-07-07 17:29:22.404918
4113	2540279	\N	2025-07-07 17:29:22.40611
4114	2509643	\N	2025-07-07 17:29:22.407102
4115	2708564	\N	2025-07-07 17:29:22.409199
4116	2837808	\N	2025-07-07 17:29:22.409876
4117	534508	\N	2025-07-07 17:29:22.411678
4118	2920182	\N	2025-07-07 17:29:22.412265
4119	4010955	\N	2025-07-07 17:29:22.413664
4120	4250696	\N	2025-07-07 17:29:22.414229
4121	4373932	\N	2025-07-07 17:29:22.415177
4122	4565929	\N	2025-07-07 17:29:22.415738
4123	4690993	\N	2025-07-07 17:29:22.416362
4124	4975784	\N	2025-07-07 17:29:22.416931
4125	4521315	\N	2025-07-07 17:29:22.417887
4126	5356497	\N	2025-07-07 17:29:22.418437
4127	5356498	\N	2025-07-07 17:29:22.418685
4128	5356500	\N	2025-07-07 17:29:22.419049
4129	4323707	\N	2025-07-07 17:29:22.419919
4130	4484393	\N	2025-07-07 17:29:22.420507
4131	4521250	\N	2025-07-07 17:29:22.421479
4132	4498539	\N	2025-07-07 17:29:22.422526
4133	4498540	\N	2025-07-07 17:29:22.423646
4134	5413283	\N	2025-07-07 17:29:22.426729
4135	5054322	\N	2025-07-07 17:29:22.427784
4136	5054325	\N	2025-07-07 17:29:22.428353
4137	5054326	\N	2025-07-07 17:29:22.428903
4138	5155483	\N	2025-07-07 17:29:22.429452
4139	5155484	\N	2025-07-07 17:29:22.430011
4140	5283917	\N	2025-07-07 17:29:22.433955
4141	5516930	\N	2025-07-07 17:29:22.434946
4142	4794432	\N	2025-07-07 17:29:22.439693
4143	2714687	\N	2025-07-07 17:29:22.441644
4144	2582130	\N	2025-07-07 17:29:22.44315
4145	4344622	\N	2025-07-07 17:29:22.443737
4146	4463312	\N	2025-07-07 17:29:22.444307
4147	5413284	\N	2025-07-07 17:29:22.447688
4148	5413286	\N	2025-07-07 17:29:22.449789
4149	4270198	\N	2025-07-07 17:29:22.453757
4150	4083912	\N	2025-07-07 17:29:22.45645
4151	5450053	\N	2025-07-07 17:29:22.457396
4152	4195021	\N	2025-07-07 17:29:22.459004
4153	4379003	\N	2025-07-07 17:29:22.460403
4154	2976432	\N	2025-07-07 17:29:22.462159
4155	2512790	\N	2025-07-07 17:29:22.463203
4156	2421904	\N	2025-07-07 17:29:22.464609
4157	4189648	\N	2025-07-07 17:29:22.466373
4158	4997189	\N	2025-07-07 17:29:22.466957
4159	5486254	\N	2025-07-07 17:29:22.467518
4160	4601864	\N	2025-07-07 17:29:22.468514
4161	4044135	\N	2025-07-07 17:29:22.473903
4162	4044137	\N	2025-07-07 17:29:22.474674
4163	5104623	\N	2025-07-07 17:29:22.474953
4164	5104634	\N	2025-07-07 17:29:22.475355
4165	4278920	\N	2025-07-07 17:29:22.477259
4166	2959429	\N	2025-07-07 17:29:22.480392
4167	4923838	\N	2025-07-07 17:29:22.481112
4168	5437514	\N	2025-07-07 17:29:22.48257
4169	5510337	\N	2025-07-07 17:29:22.492803
4170	5187032	\N	2025-07-07 17:29:22.493298
4171	2985484	\N	2025-07-07 17:29:22.494813
4172	4143919	\N	2025-07-07 17:29:22.495066
4173	4143921	\N	2025-07-07 17:29:22.495443
4174	5533780	\N	2025-07-07 17:29:22.495819
4175	2975247	\N	2025-07-07 17:29:22.49637
4176	49598	\N	2025-07-07 17:29:22.497447
4177	4570095	\N	2025-07-07 17:29:22.498053
4178	1790834	\N	2025-07-07 17:29:22.498743
4179	2879874	\N	2025-07-07 17:29:22.4995
4180	4106631	\N	2025-07-07 17:29:22.501299
4181	4328972	\N	2025-07-07 17:29:22.50194
4182	4561635	\N	2025-07-07 17:29:22.502485
4183	5513950	\N	2025-07-07 17:29:22.503119
4184	5513952	\N	2025-07-07 17:29:22.503892
4185	2004334	\N	2025-07-07 17:29:22.504456
4186	4172312	\N	2025-07-07 17:29:22.507032
4187	4328973	\N	2025-07-07 17:29:22.507322
4188	4879923	\N	2025-07-07 17:29:22.507735
4189	2695727	\N	2025-07-07 17:29:22.509448
4190	2957482	\N	2025-07-07 17:29:22.51005
4191	528114	\N	2025-07-07 17:29:22.511418
4192	2883889	\N	2025-07-07 17:29:22.512346
4193	2017320	\N	2025-07-07 17:29:22.512953
4194	2017322	\N	2025-07-07 17:29:22.527453
4195	2670055	\N	2025-07-07 17:29:22.533291
4196	4847604	\N	2025-07-07 17:29:22.536478
4197	4792615	\N	2025-07-07 17:29:22.546877
4198	4882686	\N	2025-07-07 17:29:22.549357
4199	5163857	\N	2025-07-07 17:29:22.551387
4200	2197624	\N	2025-07-07 17:29:22.557552
4201	4934746	\N	2025-07-07 17:29:22.560089
4202	5075752	\N	2025-07-07 17:29:22.575143
4203	4020108	\N	2025-07-07 17:29:22.579906
4204	2650483	\N	2025-07-07 17:29:22.587388
4205	2422705	\N	2025-07-07 17:29:22.587961
4206	712785	\N	2025-07-07 17:29:22.589942
4207	4934747	\N	2025-07-07 17:29:22.597696
4208	4198630	\N	2025-07-07 17:29:22.608493
4209	2644981	\N	2025-07-07 17:29:22.612671
4210	5034895	\N	2025-07-07 17:29:22.614517
4211	5405309	\N	2025-07-07 17:29:22.615172
4212	2707220	\N	2025-07-07 17:29:22.616121
4213	2708083	\N	2025-07-07 17:29:22.617136
4214	4843378	\N	2025-07-07 17:29:22.618642
4215	4099176	\N	2025-07-07 17:29:22.619303
4216	4339086	\N	2025-07-07 17:29:22.622124
\.


--
-- Data for Name: links; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.links (id, user_id, w1_id, w2_id, workspace_id, disabled, options, closed, deleted, created, last_updated) FROM stdin;
\.


--
-- Data for Name: llm_chats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.llm_chats (id, name, user_id, llm_credential_id, llm_prompt_id, created, disabled_message, disabled_until) FROM stdin;
\.


--
-- Data for Name: llm_credentials; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.llm_credentials (id, name, user_id, endpoint, config, is_default, result_path, created) FROM stdin;
\.


--
-- Data for Name: llm_messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.llm_messages (id, chat_id, user_id, message, created) FROM stdin;
\.


--
-- Data for Name: llm_prompts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.llm_prompts (id, name, description, user_id, prompt, created) FROM stdin;
1	Chat	Basic chat	135539d6-77e8-448e-9f03-4dbaa02000f2	You are an assistant for a PostgreSQL based software called Prostgles Desktop.\nAssist user with any queries they might have. Do not add empty lines in your sql response.\nReply with a full and concise answer that does not require further clarification or revisions.\nBelow is the database schema they're currently working with:\n\n${schema}	2025-06-30 10:04:03.728534
2	Dashboards	Create dashboards. Claude Sonnet recommended	135539d6-77e8-448e-9f03-4dbaa02000f2	You are an assistant for a PostgreSQL based software called Prostgles Desktop.\nAssist user with any queries they might have.\nBelow is the database schema they're currently working with:\n\n${schema}\n\nUsing dashboard structure below create workspaces with useful views my current schema.\nReturn only a valid, markdown compatible json of this format: { prostglesWorkspaces: WorkspaceInsertModel[] }\n\n${dashboardTypes}	2025-06-30 10:04:03.731729
\.


--
-- Data for Name: login_attempts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.login_attempts (id, type, auth_type, username, created, failed, magic_link_id, sid, auth_provider, ip_address, ip_address_remote, x_real_ip, user_agent, info) FROM stdin;
\.


--
-- Data for Name: logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.logs (id, connection_id, type, command, table_name, sid, tx_info, socket_id, duration, data, error, has_error, created) FROM stdin;
\.


--
-- Data for Name: logs_aplicacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.logs_aplicacion (id, nivel, mensaje, usuario, fecha) FROM stdin;
\.


--
-- Data for Name: magic_links; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.magic_links (id, user_id, magic_link, magic_link_used, expires, session_expires) FROM stdin;
\.


--
-- Data for Name: published_methods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.published_methods (id, name, description, connection_id, arguments, run, "outputTable") FROM stdin;
\.


--
-- Data for Name: schema_version; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schema_version (id, table_config) FROM stdin;
4	{"logs": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "sid": "TEXT", "data": "JSONB", "type": "TEXT", "error": "JSON", "command": "TEXT", "created": "TIMESTAMP DEFAULT NOW()", "tx_info": "JSONB", "duration": "NUMERIC", "has_error": "BOOLEAN", "socket_id": "TEXT", "table_name": "TEXT", "connection_id": "UUID"}}, "links": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "w1_id": "UUID NOT NULL REFERENCES windows(id)  ON DELETE CASCADE", "w2_id": "UUID NOT NULL REFERENCES windows(id)  ON DELETE CASCADE", "closed": "BOOLEAN DEFAULT FALSE", "created": "TIMESTAMP DEFAULT NOW()", "deleted": "BOOLEAN DEFAULT FALSE", "options": {"jsonbSchema": {"oneOfType": [{"type": {"enum": ["table"]}, "colorArr": {"type": "number[]", "optional": true}, "tablePath": {"optional": false, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "Table path from w1.table_name to w2.table_name"}}, {"sql": {"type": "string", "optional": true, "description": "Defined if chart links to SQL statement"}, "type": {"enum": ["map"]}, "columns": {"arrayOfType": {"name": {"type": "string", "description": "Geometry/Geography column"}, "colorArr": "number[]"}}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}, "mapIcons": {"optional": true, "oneOfType": [{"type": {"enum": ["fixed"]}, "iconPath": "string"}, {"type": {"enum": ["conditional"]}, "columnName": "string", "conditions": {"arrayOfType": {"value": "any", "iconPath": "string"}}}]}, "dataSource": {"optional": true, "oneOfType": [{"sql": "string", "type": {"enum": ["sql"], "description": "Show data from an SQL query within an editor. Will not reflect latest changes to that query (must be re-added)"}, "withStatement": "string"}, {"type": {"enum": ["table"], "description": "Shows data from an opened table window. Any filters from that table will apply to the chart as well"}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}}, {"type": {"enum": ["local-table"], "description": "Shows data from postgres table not connected to any window (w1_id === w2_id === current chart window). Custom filters can be added"}, "localTableName": {"type": "string"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}]}, "mapShowText": {"type": {"columnName": {"type": "string"}}, "optional": true}, "mapColorMode": {"optional": true, "oneOfType": [{"type": {"enum": ["fixed"]}, "colorArr": "number[]"}, {"max": "number", "min": "number", "type": {"enum": ["scale"]}, "columnName": "string", "maxColorArr": "number[]", "minColorArr": "number[]"}, {"type": {"enum": ["conditional"]}, "columnName": "string", "conditions": {"arrayOfType": {"value": "any", "colorArr": "number[]"}}}]}, "osmLayerQuery": {"type": "string", "optional": true, "description": "If provided then this is a OSM layer (w1_id === w2_id === current chart window)"}, "localTableName": {"type": "string", "optional": true, "description": "If provided then this is a local layer (w1_id === w2_id === current chart window)"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}, {"sql": {"type": "string", "optional": true, "description": "Defined if chart links to SQL statement"}, "type": {"enum": ["timechart"]}, "columns": {"arrayOfType": {"name": {"type": "string", "description": "Date column"}, "colorArr": "number[]", "statType": {"type": {"funcName": {"enum": ["$min", "$max", "$countAll", "$avg", "$sum"]}, "numericColumn": "string"}, "optional": true}}}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}, "dataSource": {"optional": true, "oneOfType": [{"sql": "string", "type": {"enum": ["sql"], "description": "Show data from an SQL query within an editor. Will not reflect latest changes to that query (must be re-added)"}, "withStatement": "string"}, {"type": {"enum": ["table"], "description": "Shows data from an opened table window. Any filters from that table will apply to the chart as well"}, "joinPath": {"optional": true, "arrayOfType": {"on": {"arrayOf": {"record": {"values": "any"}}}, "table": "string"}, "description": "When adding a chart this allows showing data from a table that joins to the current table"}}, {"type": {"enum": ["local-table"], "description": "Shows data from postgres table not connected to any window (w1_id === w2_id === current chart window). Custom filters can be added"}, "localTableName": {"type": "string"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}]}, "otherColumns": {"optional": true, "arrayOfType": {"name": "string", "label": {"type": "string", "optional": true}, "udt_name": "string"}}, "groupByColumn": {"type": "string", "optional": true, "description": "Used by timechart"}, "localTableName": {"type": "string", "optional": true, "description": "If provided then this is a local layer (w1_id === w2_id === current chart window)"}, "smartGroupFilter": {"optional": true, "oneOfType": [{"$and": "any[]"}, {"$or": "any[]"}]}}]}}, "user_id": "UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE", "disabled": "boolean", "last_updated": "BIGINT NOT NULL", "workspace_id": "UUID REFERENCES workspaces(id) ON DELETE SET NULL"}}, "stats": {"columns": {"cmd": {"info": {"hint": "Command with all its arguments as a string"}, "sqlDefinition": "TEXT"}, "cpu": {"info": {"hint": "CPU Utilisation. CPU time used divided by the time the process has been running. It will not add up to 100% unless you are lucky"}, "sqlDefinition": "NUMERIC"}, "mem": {"info": {"hint": "Ratio of the process's resident set size  to the physical memory on the machine, expressed as a percentage"}, "sqlDefinition": "NUMERIC"}, "mhz": {"info": {"hint": "Core MHz value"}, "sqlDefinition": "TEXT"}, "pid": "INTEGER NOT NULL", "datid": "INTEGER", "query": {"info": {"hint": "Text of this backend's most recent query. If state is active this field shows the currently executing query. In all other states, it shows the last query that was executed. By default the query text is truncated at 1024 bytes; this value can be changed via the parameter track_activity_query_size."}, "sqlDefinition": "TEXT"}, "state": {"info": {"hint": "Current overall state of this backend. Possible values are: active: The backend is executing a query. idle: The backend is waiting for a new client command. idle in transaction: The backend is in a transaction, but is not currently executing a query. idle in transaction (aborted): This state is similar to idle in transaction, except one of the statements in the transaction caused an error. fastpath function call: The backend is executing a fast-path function. disabled: This state is reported if track_activities is disabled in this backend."}, "sqlDefinition": "TEXT"}, "datname": "TEXT", "usename": {"info": {"hint": "Name of the user logged into this backend"}, "sqlDefinition": "TEXT"}, "usesysid": "INTEGER", "memPretty": {"info": {"hint": "mem value as string"}, "sqlDefinition": "TEXT"}, "blocked_by": {"info": {"hint": "Process ID(s) of the sessions that are blocking the server process with the specified process ID from acquiring a lock. One server process blocks another if it either holds a lock that conflicts with the blocked process's lock request (hard block), or is waiting for a lock that would conflict with the blocked process's lock request and is ahead of it in the wait queue (soft block). When using parallel queries the result always lists client-visible process IDs (that is, pg_backend_pid results) even if the actual lock is held or awaited by a child worker process. As a result of that, there may be duplicated PIDs in the result. Also note that when a prepared transaction holds a conflicting lock, it will be represented by a zero process ID."}, "sqlDefinition": "INTEGER[]"}, "wait_event": {"info": {"hint": "Wait event name if backend is currently waiting, otherwise NULL. See Table 28.5 through Table 28.13."}, "sqlDefinition": "TEXT"}, "xact_start": {"info": {"hint": "Time when this process' current transaction was started, or null if no transaction is active. If the current query is the first of its transaction, this column is equal to the query_start column."}, "sqlDefinition": "TEXT"}, "backend_xid": {"info": {"hint": "Top-level transaction identifier of this backend, if any."}, "sqlDefinition": "TEXT"}, "client_addr": {"info": {"hint": "IP address of the client connected to this backend. If this field is null, it indicates either that the client is connected via a Unix socket on the server machine or that this is an internal process such as autovacuum."}, "sqlDefinition": "TEXT"}, "client_port": {"info": {"hint": "TCP port number that the client is using for communication with this backend, or -1 if a Unix socket is used. If this field is null, it indicates that this is an internal server process."}, "sqlDefinition": "INTEGER"}, "query_start": {"info": {"hint": "Time when the currently active query was started, or if state is not active, when the last query was started"}, "sqlDefinition": "TIMESTAMP"}, "backend_type": {"info": {"hint": "Type of current backend. Possible types are autovacuum launcher, autovacuum worker, logical replication launcher, logical replication worker, parallel worker, background writer, client backend, checkpointer, archiver, startup, walreceiver, walsender and walwriter. In addition, background workers registered by extensions may have additional types."}, "sqlDefinition": "TEXT"}, "backend_xmin": {"info": {"hint": "The current backend's xmin horizon."}, "sqlDefinition": "TEXT"}, "state_change": {"info": {"hint": "Time when the state was last changed"}, "sqlDefinition": "TEXT"}, "backend_start": {"info": {"hint": "Time when this process was started. For client backends, this is the time the client connected to the server."}, "sqlDefinition": "TEXT"}, "connection_id": "UUID NOT NULL REFERENCES connections(id) ON DELETE CASCADE", "id_query_hash": {"info": {"hint": "Computed query identifier (md5(pid || query)) used in stopping queries"}, "sqlDefinition": "TEXT"}, "blocked_by_num": "INTEGER NOT NULL DEFAULT 0", "client_hostname": {"info": {"hint": "Host name of the connected client, as reported by a reverse DNS lookup of client_addr. This field will only be non-null for IP connections, and only when log_hostname is enabled."}, "sqlDefinition": "TEXT"}, "wait_event_type": {"info": {"hint": "The type of event for which the backend is waiting, if any; otherwise NULL. See Table 28.4."}, "sqlDefinition": "TEXT"}, "application_name": {"info": {"hint": "Name of the application that is connected to this backend"}, "sqlDefinition": "TEXT"}}, "constraints": {"stats_pkey": "PRIMARY KEY(pid, connection_id)"}}, "users": {"columns": {"id": {"sqlDefinition": "UUID PRIMARY KEY DEFAULT gen_random_uuid()"}, "2fa": {"nullable": true, "jsonbSchemaType": {"secret": {"type": "string"}, "enabled": {"type": "boolean"}, "recoveryCode": {"type": "string"}}}, "name": {"info": {"hint": "Display name, if empty username will be shown"}, "sqlDefinition": "TEXT"}, "type": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'default' REFERENCES user_types (id)"}, "email": {"sqlDefinition": "TEXT"}, "status": {"info": {"hint": "Only active users can access the system"}, "sqlDefinition": "TEXT NOT NULL DEFAULT 'active' REFERENCES user_statuses (id)"}, "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "options": {"nullable": true, "jsonbSchemaType": {"theme": {"enum": ["dark", "light", "from-system"], "optional": true}, "showStateDB": {"type": "boolean", "optional": true, "description": "Show the prostgles database in the connections list"}, "viewedSQLTips": {"type": "boolean", "optional": true, "description": "Will hide SQL tips if true"}, "viewedAccessInfo": {"type": "boolean", "optional": true, "description": "Will hide passwordless user tips if true"}, "hideNonSSLWarning": {"type": "boolean", "optional": true, "description": "Hides the top warning when accessing the website over an insecure connection (non-HTTPS)"}}}, "password": {"info": {"hint": "Hashed with the user id on insert/update"}, "sqlDefinition": "TEXT NOT NULL"}, "username": {"sqlDefinition": "TEXT NOT NULL UNIQUE CHECK(length(username) > 0)"}, "last_updated": {"sqlDefinition": "BIGINT DEFAULT EXTRACT(EPOCH FROM NOW()) * 1000"}, "registration": {"nullable": true, "jsonbSchema": {"oneOfType": [{"type": {"enum": ["password-w-email-confirmation"]}, "email_confirmation": {"oneOfType": [{"date": "Date", "status": {"enum": ["confirmed"]}}, {"date": "Date", "status": {"enum": ["pending"]}, "confirmation_code": {"type": "string"}}]}}, {"date": "Date", "type": {"enum": ["magic-link"]}, "used_on": {"type": "Date", "optional": true}, "otp_code": {"type": "string"}}, {"type": {"enum": ["OAuth"]}, "profile": "any", "user_id": "string", "provider": {"enum": ["google", "facebook", "github", "microsoft", "customOAuth"], "description": "OAuth provider name. E.g.: google, github"}}]}}, "auth_provider": {"info": {"hint": "OAuth provider name. E.g.: google, github"}, "sqlDefinition": "TEXT"}, "has_2fa_enabled": "BOOLEAN GENERATED ALWAYS AS ( (\\"2fa\\"->>'enabled')::BOOLEAN ) STORED", "passwordless_admin": {"info": {"hint": "If true and status is active: enables passwordless access for default install. First connected client will have perpetual admin access and no other users are allowed "}, "sqlDefinition": "BOOLEAN"}, "auth_provider_profile": {"info": {"hint": "OAuth provider profile data"}, "sqlDefinition": "JSONB"}, "auth_provider_user_id": {"info": {"hint": "User id"}, "sqlDefinition": "TEXT"}}, "indexes": {"Only one passwordless_admin admin account allowed": {"where": "passwordless_admin = true", "unique": true, "columns": "passwordless_admin"}}, "triggers": {"atLeastOneActiveAdmin": {"type": "after", "query": "\\n          BEGIN\\n            IF NOT EXISTS(SELECT * FROM users WHERE type = 'admin' AND status = 'active') THEN\\n              RAISE EXCEPTION 'Must have at least one active admin user';\\n            END IF;\\n\\n            RETURN NULL;\\n          END;\\n        ", "actions": ["delete", "update"], "forEach": "statement"}}, "constraints": {"passwordless_admin type AND username CHECK": "CHECK(COALESCE(passwordless_admin, false) = FALSE OR type = 'admin' AND username = 'passwordless_admin')"}}, "alerts": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "data": "JSONB", "title": "TEXT", "created": "TIMESTAMP DEFAULT NOW()", "message": "TEXT", "section": {"enum": ["access_control", "backups", "table_config", "details", "status", "methods", "file_storage", "API"], "nullable": true}, "severity": {"enum": ["info", "warning", "error"]}, "connection_id": "UUID REFERENCES connections(id) ON DELETE SET NULL", "database_config_id": "INTEGER REFERENCES database_configs(id) ON DELETE SET NULL"}}, "backups": {"columns": {"id": {"info": {"hint": "Format: dbname_datetime_uuid"}, "sqlDefinition": "TEXT PRIMARY KEY DEFAULT gen_random_uuid()"}, "status": {"jsonbSchema": {"oneOfType": [{"ok": {"type": "string"}}, {"err": {"type": "string"}}, {"loading": {"type": {"total": {"type": "number", "optional": true}, "loaded": {"type": "number"}}, "optional": true}}]}}, "created": {"sqlDefinition": "TIMESTAMP NOT NULL DEFAULT NOW()"}, "details": {"sqlDefinition": "JSONB"}, "options": {"jsonbSchema": {"oneOfType": [{"clean": {"type": "boolean"}, "command": {"enum": ["pg_dumpall"]}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "rolesOnly": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "globalsOnly": {"type": "boolean", "optional": true}}, {"clean": {"type": "boolean", "optional": true}, "create": {"type": "boolean", "optional": true}, "format": {"enum": ["p", "t", "c"]}, "command": {"enum": ["pg_dump"]}, "noOwner": {"type": "boolean", "optional": true}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "numberOfJobs": {"type": "integer", "optional": true}, "excludeSchema": {"type": "string", "optional": true}, "compressionLevel": {"type": "integer", "optional": true}}]}}, "uploaded": {"sqlDefinition": "TIMESTAMP"}, "dump_logs": {"sqlDefinition": "TEXT"}, "initiator": {"sqlDefinition": "TEXT"}, "destination": {"enum": ["Local", "Cloud", "None (temp stream)"], "nullable": false}, "restore_end": {"sqlDefinition": "TIMESTAMP"}, "sizeInBytes": {"label": "Backup file size", "sqlDefinition": "BIGINT"}, "content_type": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'application/gzip'"}, "dump_command": {"sqlDefinition": "TEXT NOT NULL"}, "last_updated": {"sqlDefinition": "TIMESTAMP NOT NULL DEFAULT NOW()"}, "restore_logs": {"sqlDefinition": "TEXT"}, "connection_id": {"info": {"hint": "If null then connection was deleted"}, "sqlDefinition": "UUID REFERENCES connections(id) ON DELETE SET NULL"}, "credential_id": {"info": {"hint": "If null then uploaded locally"}, "sqlDefinition": "INTEGER REFERENCES credentials(id) "}, "dbSizeInBytes": {"label": "Database size on disk", "sqlDefinition": "BIGINT NOT NULL"}, "restore_start": {"sqlDefinition": "TIMESTAMP"}, "local_filepath": {"sqlDefinition": "TEXT"}, "restore_status": {"nullable": true, "jsonbSchema": {"oneOfType": [{"ok": {"type": "string"}}, {"err": {"type": "string"}}, {"loading": {"type": {"total": {"type": "number"}, "loaded": {"type": "number"}}}}]}}, "restore_command": {"sqlDefinition": "TEXT"}, "restore_options": {"defaultValue": "{ \\"clean\\": true, \\"format\\": \\"c\\", \\"command\\": \\"pg_restore\\" }", "jsonbSchemaType": {"clean": {"type": "boolean"}, "create": {"type": "boolean", "optional": true}, "format": {"enum": ["p", "t", "c"]}, "command": {"enum": ["pg_restore", "psql"]}, "noOwner": {"type": "boolean", "optional": true}, "dataOnly": {"type": "boolean", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "newDbName": {"type": "string", "optional": true}, "numberOfJobs": {"type": "integer", "optional": true}, "excludeSchema": {"type": "string", "optional": true}}}, "connection_details": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'unknown connection' "}}}, "windows": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "sql": "TEXT NOT NULL DEFAULT ''", "name": "TEXT", "sort": "JSONB DEFAULT '[]'::jsonb", "type": "TEXT CHECK(type IN ('map', 'sql', 'table', 'timechart', 'card', 'method'))", "limit": "INTEGER DEFAULT 1000 CHECK(\\"limit\\" > -1 AND \\"limit\\" < 100000)", "closed": "BOOLEAN DEFAULT FALSE", "filter": "JSONB NOT NULL DEFAULT '[]'::jsonb", "having": "JSONB NOT NULL DEFAULT '[]'::jsonb", "columns": "JSONB", "created": "TIMESTAMP NOT NULL DEFAULT NOW()", "deleted": "BOOLEAN DEFAULT FALSE CHECK(NOT (type = 'sql' AND deleted = TRUE AND (options->>'sqlWasSaved')::boolean = true))", "options": "JSONB NOT NULL DEFAULT '{}'::jsonb", "user_id": "UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE", "minimised": {"info": {"hint": "Used for attached charts to hide them"}, "sqlDefinition": "BOOLEAN DEFAULT FALSE"}, "show_menu": "BOOLEAN DEFAULT FALSE", "table_oid": "INTEGER", "fullscreen": "BOOLEAN DEFAULT TRUE", "table_name": "TEXT", "method_name": "TEXT", "sql_options": {"defaultValue": {"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}, "jsonbSchemaType": {"theme": {"enum": ["vs", "vs-dark", "hc-black", "hc-light"], "optional": true}, "minimap": {"type": {"enabled": {"type": "boolean"}}, "optional": true, "description": "Shows a vertical code minimap to the right"}, "tabSize": {"type": "integer", "optional": true}, "renderMode": {"enum": ["table", "csv", "JSON"], "optional": true, "description": "Show query results in a table or a JSON"}, "lineNumbers": {"enum": ["on", "off"], "optional": true}, "executeOptions": {"enum": ["full", "block", "smallest-block"], "optional": true, "description": "Behaviour of execute (ALT + E). Defaults to 'block' \\nfull = run entire sql   \\nblock = run code block where the cursor is"}, "maxCharsPerCell": {"type": "integer", "optional": true, "description": "Defaults to 1000. Maximum number of characters to display for each cell. Useful in improving performance"}, "errorMessageDisplay": {"enum": ["tooltip", "bottom", "both"], "optional": true, "description": "Error display locations. Defaults to 'both' \\ntooltip = show within tooltip only   \\nbottom = show in bottom control bar only   \\nboth = show in both locations"}, "expandSuggestionDocs": {"type": "boolean", "optional": true, "description": "Toggle suggestions documentation tab. Requires page refresh. Enabled by default"}, "showRunningQueryStats": {"type": "boolean", "optional": true, "description": "(Experimental) Display running query stats (CPU and Memory usage) in the bottom bar"}, "acceptSuggestionOnEnter": {"enum": ["on", "smart", "off"], "optional": true, "description": "Insert suggestions on Enter. Tab is the default key"}}}, "last_updated": "BIGINT NOT NULL", "selected_sql": "TEXT NOT NULL DEFAULT ''", "workspace_id": "UUID REFERENCES workspaces(id) ON DELETE SET NULL", "nested_tables": "JSONB", "function_options": {"nullable": true, "jsonbSchemaType": {"showDefinition": {"type": "boolean", "optional": true, "description": "Show the function definition"}}}, "parent_window_id": {"info": {"hint": "If defined then this is a chart for another window and will be rendered within that parent window"}, "sqlDefinition": "UUID REFERENCES windows(id) ON DELETE CASCADE"}}}, "sessions": {"columns": {"id": "TEXT UNIQUE NOT NULL", "name": "TEXT", "type": "TEXT NOT NULL REFERENCES session_types", "active": "BOOLEAN DEFAULT TRUE", "id_num": "SERIAL PRIMARY KEY", "created": "TIMESTAMP DEFAULT NOW()", "expires": "BIGINT NOT NULL", "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "is_mobile": "BOOLEAN DEFAULT FALSE", "last_used": "TIMESTAMP DEFAULT NOW()", "socket_id": "TEXT", "user_type": "TEXT NOT NULL", "ip_address": "INET NOT NULL", "project_id": "TEXT", "user_agent": "TEXT", "is_connected": "BOOLEAN DEFAULT FALSE"}}, "llm_chats": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "name": "TEXT NOT NULL DEFAULT 'New chat'", "created": "TIMESTAMP DEFAULT NOW()", "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "llm_prompt_id": "INTEGER REFERENCES llm_prompts(id) ON DELETE SET NULL", "disabled_until": {"info": {"hint": "If set then chat is disabled until this time"}, "sqlDefinition": "TIMESTAMPTZ"}, "disabled_message": {"info": {"hint": "Message to show when chat is disabled"}, "sqlDefinition": "TEXT"}, "llm_credential_id": "INTEGER REFERENCES llm_credentials(id) ON DELETE SET NULL"}}, "user_types": {"triggers": {"atLeastOneAdminAndPublic": {"type": "after", "query": " \\n          BEGIN\\n            IF NOT EXISTS(SELECT * FROM user_types WHERE id = 'admin') \\n              OR NOT EXISTS(SELECT * FROM user_types WHERE id = 'public')\\n            THEN\\n              RAISE EXCEPTION 'admin and public user types cannot be deleted/modified';\\n            END IF;\\n  \\n            RETURN NULL;\\n          END;\\n        ", "actions": ["delete", "update"], "forEach": "statement"}}, "isLookupTable": {"values": {"admin": {"en": "Highest access level"}, "public": {"en": "Public user. Account created on login and deleted on logout"}, "default": {}}}}, "workspaces": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "icon": "TEXT", "name": "TEXT NOT NULL DEFAULT 'default workspace'", "layout": "JSONB", "created": "TIMESTAMP DEFAULT NOW()", "deleted": "BOOLEAN NOT NULL DEFAULT FALSE", "options": {"defaultValue": {"hideCounts": false, "pinnedMenu": true, "tableListSortBy": "extraInfo", "tableListEndInfo": "size", "defaultLayoutType": "tab"}, "jsonbSchemaType": {"hideCounts": {"type": "boolean", "optional": true}, "pinnedMenu": {"type": "boolean", "optional": true}, "pinnedMenuWidth": {"type": "number", "optional": true}, "tableListSortBy": {"enum": ["name", "extraInfo"], "optional": true}, "showAllMyQueries": {"type": "boolean", "optional": true}, "tableListEndInfo": {"enum": ["none", "count", "size"], "optional": true}, "defaultLayoutType": {"enum": ["row", "tab", "col"], "optional": true}}}, "user_id": "UUID NOT NULL REFERENCES users(id)  ON DELETE CASCADE", "url_path": "TEXT", "last_used": "TIMESTAMP NOT NULL DEFAULT now()", "published": {"info": {"hint": "If true then this workspace can be shared with other users through Access Control"}, "sqlDefinition": "BOOLEAN NOT NULL DEFAULT FALSE, CHECK(parent_workspace_id IS NULL OR published = FALSE)"}, "active_row": "JSONB DEFAULT '{}'::jsonb", "last_updated": "BIGINT NOT NULL", "publish_mode": "TEXT REFERENCES workspace_publish_modes ", "connection_id": "UUID NOT NULL REFERENCES connections(id)  ON DELETE CASCADE", "parent_workspace_id": "UUID REFERENCES workspaces(id) ON DELETE SET NULL"}, "constraints": {"unique_url_path": "UNIQUE(url_path)", "unique_name_per_user_perCon": "UNIQUE(connection_id, user_id, name)"}}, "connections": {"columns": {"id": "UUID PRIMARY KEY DEFAULT gen_random_uuid()", "info": {"nullable": true, "jsonbSchemaType": {"canCreateDb": {"type": "boolean", "optional": true, "description": "True if postgres user is allowed to create databases. Never gets updated"}}}, "name": "TEXT NOT NULL CHECK(LENGTH(name) > 0)", "type": {"enum": ["Standard", "Connection URI", "Prostgles"], "nullable": false}, "config": {"nullable": true, "jsonbSchemaType": {"path": "string", "enabled": "boolean"}}, "db_ssl": {"enum": ["disable", "allow", "prefer", "require", "verify-ca", "verify-full"], "nullable": false, "defaultValue": "disable"}, "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "db_conn": {"sqlDefinition": "TEXT DEFAULT ''"}, "db_host": "TEXT NOT NULL DEFAULT 'localhost'", "db_name": "TEXT NOT NULL CHECK(LENGTH(db_name) > 0)", "db_pass": "TEXT DEFAULT ''", "db_port": "INTEGER NOT NULL DEFAULT 5432", "db_user": "TEXT NOT NULL DEFAULT ''", "user_id": "UUID REFERENCES users(id) ON DELETE CASCADE", "prgl_url": {"sqlDefinition": "TEXT"}, "url_path": {"info": {"hint": "URL path to be used instead of the connection uuid"}, "sqlDefinition": "TEXT CHECK(LENGTH(url_path) > 0 AND url_path ~ '^[a-z0-9-]+$')"}, "is_state_db": {"info": {"hint": "If true then this DB is used to run the dashboard"}, "sqlDefinition": "BOOLEAN"}, "on_mount_ts": {"info": {"hint": "On mount typescript function. Must export const onMount"}, "sqlDefinition": "TEXT"}, "prgl_params": {"sqlDefinition": "JSONB"}, "last_updated": {"sqlDefinition": "BIGINT NOT NULL DEFAULT 0"}, "table_options": {"nullable": true, "jsonbSchema": {"record": {"values": {"type": {"icon": {"type": "string", "optional": true}}}, "partial": true}}}, "db_watch_shema": {"sqlDefinition": "BOOLEAN DEFAULT TRUE"}, "ssl_certificate": {"sqlDefinition": "TEXT"}, "db_schema_filter": {"nullable": true, "jsonbSchema": {"oneOf": [{"record": {"values": {"enum": [1]}}}, {"record": {"values": {"enum": [0]}}}]}}, "disable_realtime": {"info": {"hint": "If true then subscriptions and syncs will not work. Used to ensure prostgles schema is not created and nothing is changed in the database"}, "sqlDefinition": "BOOLEAN DEFAULT FALSE"}, "on_mount_ts_disabled": {"info": {"hint": "If true then On mount typescript will not be executed"}, "sqlDefinition": "BOOLEAN"}, "db_connection_timeout": "INTEGER CHECK(db_connection_timeout > 0)", "ssl_client_certificate": {"sqlDefinition": "TEXT"}, "ssl_reject_unauthorized": {"info": {"hint": "If true, the server certificate is verified against the list of supplied CAs. \\nAn error event is emitted if verification fails"}, "sqlDefinition": "BOOLEAN"}, "ssl_client_certificate_key": {"sqlDefinition": "TEXT"}}, "constraints": {"uniqueConName": "UNIQUE(name, user_id)", "database_config_fkey": "FOREIGN KEY (db_name, db_host, db_port) REFERENCES database_configs( db_name, db_host, db_port )", "Check connection type": "CHECK (\\n            type IN ('Standard', 'Connection URI', 'Prostgles') \\n            AND (type <> 'Connection URI' OR length(db_conn) > 1) \\n            AND (type <> 'Standard' OR length(db_host) > 1) \\n            AND (type <> 'Prostgles' OR length(prgl_url) > 0)\\n          )", "unique_connection_url_path": "UNIQUE(url_path)"}}, "credentials": {"columns": {"id": "SERIAL PRIMARY KEY", "name": "TEXT NOT NULL DEFAULT ''", "type": "TEXT NOT NULL REFERENCES credential_types(id) DEFAULT 's3'", "bucket": "TEXT", "key_id": "TEXT NOT NULL", "region": "TEXT", "user_id": "UUID REFERENCES users(id) ON DELETE SET NULL", "key_secret": "TEXT NOT NULL"}, "constraints": {"Bucket or Region missing": "CHECK(type <> 's3' OR (bucket IS NOT NULL AND region IS NOT NULL))"}}, "llm_prompts": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "name": "TEXT NOT NULL DEFAULT 'New prompt'", "prompt": "TEXT NOT NULL CHECK(LENGTH(btrim(prompt)) > 0)", "created": "TIMESTAMP DEFAULT NOW()", "user_id": "UUID REFERENCES users(id) ON DELETE SET NULL", "description": "TEXT DEFAULT ''"}, "indexes": {"unique_llm_prompt_name": {"unique": true, "columns": "name, user_id"}}}, "magic_links": {"columns": {"id": "TEXT PRIMARY KEY DEFAULT gen_random_uuid()", "expires": "BIGINT NOT NULL", "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "magic_link": "TEXT", "magic_link_used": "TIMESTAMP", "session_expires": "BIGINT NOT NULL DEFAULT 0"}}, "llm_messages": {"columns": {"id": "int8 PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "chat_id": "INTEGER NOT NULL REFERENCES llm_chats(id) ON DELETE CASCADE", "created": "TIMESTAMP DEFAULT NOW()", "message": "TEXT NOT NULL", "user_id": "UUID REFERENCES users(id) ON DELETE CASCADE"}}, "session_types": {"isLookupTable": {"values": {"web": {}, "mobile": {}, "api_token": {}}}}, "user_statuses": {"isLookupTable": {"values": {"active": {}, "disabled": {}}}}, "access_control": {"columns": {"id": "SERIAL PRIMARY KEY", "name": "TEXT", "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "database_id": "INTEGER NOT NULL REFERENCES database_configs(id) ON DELETE CASCADE", "dbPermissions": {"info": {"hint": "Permission types and rules for this (connection_id) database"}, "jsonbSchema": {"oneOfType": [{"type": {"enum": ["Run SQL"], "description": "Allows complete access to the database"}, "allowSQL": {"type": "boolean", "optional": true}}, {"type": {"enum": ["All views/tables"], "description": "Custom access (View/Edit/Remove) to all tables"}, "allowAllTables": {"type": "string[]", "allowedValues": ["select", "insert", "update", "delete"]}}, {"type": {"enum": ["Custom"], "description": "Fine grained access to specific tables"}, "customTables": {"arrayOfType": {"sync": {"type": {"throttle": {"type": "integer", "optional": true}, "id_fields": {"type": "string[]"}, "allow_delete": {"type": "boolean", "optional": true}, "synced_field": {"type": "string"}}, "optional": true}, "delete": {"oneOf": ["boolean", {"type": {"filterFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "forcedFilterDetailed": {"type": "any", "optional": true}}}], "optional": true}, "insert": {"oneOf": ["boolean", {"type": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "forcedDataDetail": {"type": "any[]", "optional": true}, "checkFilterDetailed": {"type": "any", "optional": true}}}], "optional": true}, "select": {"oneOf": ["boolean", {"type": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "subscribe": {"type": {"throttle": {"type": "integer", "optional": true}}, "optional": true}, "filterFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "orderByFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "forcedFilterDetailed": {"type": "any", "optional": true}}}], "optional": true, "description": "Allows viewing data"}, "update": {"oneOf": ["boolean", {"type": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "filterFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "dynamicFields": {"optional": true, "arrayOfType": {"fields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}]}, "filterDetailed": "any"}}, "orderByFields": {"oneOf": ["string[]", {"enum": ["*", ""]}, {"record": {"values": {"enum": [1, true]}}}, {"record": {"values": {"enum": [0, false]}}}], "optional": true}, "forcedDataDetail": {"type": "any[]", "optional": true}, "checkFilterDetailed": {"type": "any", "optional": true}, "forcedFilterDetailed": {"type": "any", "optional": true}}}], "optional": true}, "tableName": "string"}}}]}}, "dbsPermissions": {"info": {"hint": "Permission types and rules for the state database"}, "nullable": true, "jsonbSchemaType": {"createWorkspaces": {"type": "boolean", "optional": true}, "viewPublishedWorkspaces": {"type": {"workspaceIds": "string[]"}, "optional": true}}}, "llm_daily_limit": {"info": {"hint": "Maximum amount of queires per user/ip per 24hours"}, "sqlDefinition": "INTEGER NOT NULL DEFAULT 0 CHECK(llm_daily_limit >= 0)"}}}, "database_stats": {"columns": {"database_config_id": "INTEGER REFERENCES database_configs(id) ON DELETE SET NULL"}}, "login_attempts": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "sid": "TEXT", "info": "TEXT", "type": {"enum": ["web", "api_token", "mobile"], "nullable": false, "defaultValue": "web"}, "failed": "BOOLEAN", "created": "TIMESTAMP DEFAULT NOW()", "username": "TEXT", "auth_type": {"enum": ["session-id", "registration", "email-confirmation", "magic-link-registration", "magic-link", "otp-code", "login", "oauth"]}, "x_real_ip": "TEXT NOT NULL", "ip_address": "INET NOT NULL", "user_agent": "TEXT NOT NULL", "auth_provider": "TEXT CHECK(auth_type <> 'oauth' OR auth_provider IS NOT NULL)", "magic_link_id": "TEXT", "ip_address_remote": "TEXT NOT NULL"}}, "alert_viewed_by": {"columns": {"id": "BIGSERIAL PRIMARY KEY", "viewed": "TIMESTAMP DEFAULT NOW()", "user_id": "UUID REFERENCES users(id) ON DELETE CASCADE", "alert_id": "BIGINT REFERENCES alerts(id) ON DELETE CASCADE"}}, "global_settings": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "updated_at": {"sqlDefinition": "TIMESTAMP NOT NULL DEFAULT now()"}, "updated_by": {"enum": ["user", "app"], "defaultValue": "app"}, "allowed_ips": {"info": {"hint": "List of allowed IP addresses in ipv4 or ipv6 format"}, "label": "Allowed IPs and subnets", "sqlDefinition": "cidr[] NOT NULL DEFAULT '{}'"}, "enable_logs": {"info": {"hint": "Logs are saved in the logs table from the state database"}, "label": "Enable logs (experimental)", "sqlDefinition": "boolean NOT NULL DEFAULT FALSE"}, "tableConfig": {"info": {"hint": "Schema used to create prostgles-ui"}, "sqlDefinition": "JSONB"}, "trust_proxy": {"info": {"hint": "If true then will use the IP from 'X-Forwarded-For' header"}, "sqlDefinition": "boolean NOT NULL DEFAULT FALSE"}, "allowed_origin": {"info": {"hint": "Specifies which domains can access this app in a cross-origin manner. \\nSets the Access-Control-Allow-Origin header. \\nUse '*' or a specific URL to allow API access"}, "label": "Allow-Origin", "sqlDefinition": "TEXT"}, "auth_providers": {"info": {"hint": "The provided credentials will allow users to register and sign in. The redirect uri format is {website_url}/auth/{providerName}/callback"}, "nullable": true, "jsonbSchemaType": {"email": {"optional": true, "oneOfType": [{"smtp": {"oneOfType": [{"host": {"type": "string"}, "pass": {"type": "string"}, "port": {"type": "number"}, "type": {"enum": ["smtp"]}, "user": {"type": "string"}, "secure": {"type": "boolean", "optional": true}, "rejectUnauthorized": {"type": "boolean", "optional": true}}, {"type": {"enum": ["aws-ses"]}, "region": {"type": "string"}, "accessKeyId": {"type": "string"}, "sendingRate": {"type": "integer", "optional": true}, "secretAccessKey": {"type": "string"}}]}, "enabled": {"type": "boolean", "optional": true}, "signupType": {"enum": ["withMagicLink"]}, "emailTemplate": {"type": {"body": "string", "from": "string", "subject": "string"}, "title": "Email template used for sending auth emails. Must contain placeholders for the url: ${url}"}, "emailConfirmationEnabled": {"type": "boolean", "title": "Enable email confirmation", "optional": true}}, {"smtp": {"oneOfType": [{"host": {"type": "string"}, "pass": {"type": "string"}, "port": {"type": "number"}, "type": {"enum": ["smtp"]}, "user": {"type": "string"}, "secure": {"type": "boolean", "optional": true}, "rejectUnauthorized": {"type": "boolean", "optional": true}}, {"type": {"enum": ["aws-ses"]}, "region": {"type": "string"}, "accessKeyId": {"type": "string"}, "sendingRate": {"type": "integer", "optional": true}, "secretAccessKey": {"type": "string"}}]}, "enabled": {"type": "boolean", "optional": true}, "signupType": {"enum": ["withPassword"]}, "emailTemplate": {"type": {"body": "string", "from": "string", "subject": "string"}, "title": "Email template used for sending auth emails. Must contain placeholders for the url: ${url}"}, "minPasswordLength": {"type": "integer", "title": "Minimum password length", "optional": true}, "emailConfirmationEnabled": {"type": "boolean", "title": "Enable email confirmation", "optional": true}}]}, "github": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["read:user", "user:email"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "google": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["profile", "email", "calendar", "calendar.readonly", "calendar.events", "calendar.events.readonly"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "facebook": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["email", "public_profile", "user_birthday", "user_friends", "user_gender", "user_hometown"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "microsoft": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]", "allowedValues": ["openid", "profile", "email", "offline_access", "User.Read", "User.ReadBasic.All", "User.Read.All"]}, "prompt": {"enum": ["login", "none", "consent", "select_account", "create"]}}, "optional": true}, "clientID": {"type": "string"}, "clientSecret": {"type": "string"}}, "optional": true}, "customOAuth": {"type": {"enabled": {"type": "boolean", "optional": true}, "authOpts": {"type": {"scope": {"type": "string[]"}}, "optional": true}, "clientID": {"type": "string"}, "tokenURL": {"type": "string"}, "displayName": {"type": "string"}, "clientSecret": {"type": "string"}, "displayIconPath": {"type": "string", "optional": true}, "authorizationURL": {"type": "string"}}, "optional": true}, "website_url": {"type": "string", "title": "Website URL"}, "created_user_type": {"type": "string", "title": "User type assigned to new users. Defaults to 'default'", "optional": true}}}, "login_rate_limit": {"info": {"hint": "List of allowed IP addresses in ipv4 or ipv6 format"}, "label": "Failed login rate limit options", "defaultValue": {"groupBy": "ip", "maxAttemptsPerHour": 5}, "jsonbSchemaType": {"groupBy": {"enum": ["x-real-ip", "remote_ip", "ip"], "description": "The IP address used to group login attempts"}, "maxAttemptsPerHour": {"type": "integer", "description": "Maximum number of login attempts allowed per hour"}}}, "allowed_ips_enabled": {"info": {"hint": "If enabled then only allowed IPs can connect"}, "sqlDefinition": "BOOLEAN NOT NULL DEFAULT FALSE CHECK(allowed_ips_enabled = FALSE OR cardinality(allowed_ips) > 0)"}, "session_max_age_days": {"info": {"max": 9007199254740991, "min": 1, "hint": "Number of days a user will stay logged in"}, "sqlDefinition": "INTEGER NOT NULL DEFAULT 14 CHECK(session_max_age_days > 0)"}, "prostgles_registration": {"info": {"hint": "Registration options"}, "nullable": true, "jsonbSchemaType": {"email": {"type": "string"}, "token": {"type": "string"}, "enabled": {"type": "boolean"}}}, "login_rate_limit_enabled": {"info": {"hint": "If enabled then each client defined by <groupBy> that fails <maxAttemptsPerHour> in an hour will not be able to login for the rest of the hour"}, "label": "Enable failed login rate limit", "sqlDefinition": "BOOLEAN NOT NULL DEFAULT TRUE"}, "magic_link_validity_days": {"info": {"max": 9007199254740991, "min": 1, "hint": "Number of days a magic link can be used to log in"}, "sqlDefinition": "INTEGER NOT NULL DEFAULT 1 CHECK(magic_link_validity_days > 0)"}, "pass_process_env_vars_to_server_side_functions": {"info": {"hint": "If true then all environment variables will be passed to the server side function nodejs. Use at your own risk"}, "sqlDefinition": "BOOLEAN NOT NULL DEFAULT FALSE"}}, "triggers": {"Update updated_at": {"type": "before", "query": "\\n          BEGIN\\n            NEW.updated_at = now();\\n            RETURN NEW;\\n          END;\\n        ", "actions": ["update"], "forEach": "row"}}}, "llm_credentials": {"columns": {"id": "INTEGER PRIMARY KEY GENERATED ALWAYS AS IDENTITY", "name": "TEXT NOT NULL DEFAULT 'Default credential'", "config": {"jsonbSchema": {"oneOfType": [{"model": {"type": "string"}, "API_Key": {"type": "string"}, "Provider": {"enum": ["OpenAI"]}, "temperature": {"type": "number", "optional": true}, "response_format": {"enum": ["json", "text", "srt", "verbose_json", "vtt"], "optional": true}, "presence_penalty": {"type": "number", "optional": true}, "frequency_penalty": {"type": "number", "optional": true}, "max_completion_tokens": {"type": "integer", "optional": true}}, {"model": {"type": "string"}, "API_Key": {"type": "string"}, "Provider": {"enum": ["Anthropic"]}, "max_tokens": {"type": "integer"}, "anthropic-version": {"type": "string"}}, {"body": {"record": {"values": "string"}, "optional": true}, "headers": {"record": {"values": "string"}, "optional": true}, "Provider": {"enum": ["Custom"]}}, {"API_Key": {"type": "string"}, "Provider": {"enum": ["Prostgles"]}}]}, "defaultValue": {"model": "gpt-4o", "API_Key": "", "Provider": "OpenAI"}}, "created": {"sqlDefinition": "TIMESTAMP DEFAULT NOW()"}, "user_id": "UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE", "endpoint": {"sqlDefinition": "TEXT NOT NULL DEFAULT 'https://api.openai.com/v1/chat/completions'"}, "is_default": {"info": {"hint": "If true then this is the default credential"}, "sqlDefinition": "BOOLEAN DEFAULT FALSE"}, "result_path": {"info": {"hint": "Will use corect defaults for OpenAI and Anthropic. Path to text response. E.g.: choices,0,message,content"}, "sqlDefinition": "_TEXT "}}, "indexes": {"unique_default": {"where": "is_default = TRUE", "unique": true, "columns": "is_default"}, "unique_llm_credential_name": {"unique": true, "columns": "name, user_id"}}}, "credential_types": {"isLookupTable": {"values": {"s3": {}}}}, "database_configs": {"columns": {"id": "SERIAL PRIMARY KEY", "db_host": "TEXT NOT NULL", "db_name": "TEXT NOT NULL", "db_port": "INTEGER NOT NULL", "sync_users": "BOOLEAN DEFAULT FALSE", "table_config": {"info": {"hint": "Table configurations"}, "nullable": true, "jsonbSchema": {"record": {"values": {"oneOfType": [{"isLookupTable": {"type": {"values": {"record": {"values": {"type": "string", "optional": true}}}}}}, {"columns": {"record": {"values": {"oneOf": ["string", {"type": {"hint": {"type": "string", "optional": true}, "isText": {"type": "boolean", "optional": true}, "trimmed": {"type": "boolean", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "defaultValue": {"type": "any", "optional": true}}}, {"type": {"jsonbSchema": {"oneOfType": [{"type": {"enum": ["string", "number", "boolean", "Date", "time", "timestamp", "string[]", "number[]", "boolean[]", "Date[]", "time[]", "timestamp[]"]}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}}, {"type": {"enum": ["Lookup", "Lookup[]"]}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}}, {"type": {"enum": ["object"]}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}}]}}}]}}, "description": "Column definitions and hints"}}]}}}}, "backups_config": {"info": {"hint": "Automatic backups configurations"}, "nullable": true, "jsonbSchemaType": {"err": {"type": "string", "nullable": true, "optional": true}, "hour": {"type": "integer", "optional": true}, "enabled": {"type": "boolean", "optional": true}, "keepLast": {"type": "integer", "optional": true}, "dayOfWeek": {"type": "integer", "optional": true}, "frequency": {"enum": ["daily", "monthly", "weekly", "hourly"]}, "dayOfMonth": {"type": "integer", "optional": true}, "cloudConfig": {"type": {"credential_id": {"type": "number", "nullable": true, "optional": true}}, "nullable": true}, "dump_options": {"oneOfType": [{"clean": {"type": "boolean"}, "command": {"enum": ["pg_dumpall"]}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "rolesOnly": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "globalsOnly": {"type": "boolean", "optional": true}}, {"clean": {"type": "boolean", "optional": true}, "create": {"type": "boolean", "optional": true}, "format": {"enum": ["p", "t", "c"]}, "command": {"enum": ["pg_dump"]}, "noOwner": {"type": "boolean", "optional": true}, "dataOnly": {"type": "boolean", "optional": true}, "encoding": {"type": "string", "optional": true}, "ifExists": {"type": "boolean", "optional": true}, "keepLogs": {"type": "boolean", "optional": true}, "schemaOnly": {"type": "boolean", "optional": true}, "numberOfJobs": {"type": "integer", "optional": true}, "excludeSchema": {"type": "string", "optional": true}, "compressionLevel": {"type": "integer", "optional": true}}]}}}, "table_config_ts": {"info": {"hint": "Table configurations from typescript. Must export const tableConfig"}, "sqlDefinition": "TEXT"}, "rest_api_enabled": "BOOLEAN DEFAULT FALSE", "file_table_config": {"info": {"hint": "File storage configurations"}, "nullable": true, "jsonbSchemaType": {"fileTable": {"type": "string", "optional": true}, "storageType": {"oneOfType": [{"type": {"enum": ["local"]}}, {"type": {"enum": ["S3"]}, "credential_id": {"type": "number"}}]}, "delayedDelete": {"type": {"deleteAfterNDays": {"type": "number"}, "checkIntervalHours": {"type": "number", "optional": true}}, "optional": true}, "referencedTables": {"type": "any", "optional": true}}}, "table_config_ts_disabled": {"info": {"hint": "If true then Table configurations will not be executed"}, "sqlDefinition": "BOOLEAN"}}, "constraints": {"uniqueDatabase": {"type": "UNIQUE", "content": "db_name, db_host, db_port"}}}, "published_methods": {"columns": {"id": "SERIAL PRIMARY KEY", "run": "TEXT NOT NULL DEFAULT 'export const run: ProstglesMethod = async (args, { db, dbo, user }) => {\\n  \\n}'", "name": "TEXT NOT NULL DEFAULT 'Method name'", "arguments": {"nullable": false, "jsonbSchema": {"title": "Arguments", "arrayOf": {"oneOfType": [{"name": {"type": "string", "title": "Argument name"}, "type": {"enum": ["any", "string", "number", "boolean", "Date", "time", "timestamp", "string[]", "number[]", "boolean[]", "Date[]", "time[]", "timestamp[]"], "title": "Data type"}, "optional": {"type": "boolean", "title": "Optional", "optional": true}, "defaultValue": {"type": "string", "optional": true}, "allowedValues": {"type": "string[]", "title": "Allowed values", "optional": true}}, {"name": {"type": "string", "title": "Argument name"}, "type": {"enum": ["Lookup", "Lookup[]"], "title": "Data type"}, "lookup": {"title": "Table column", "lookup": {"type": "data-def", "table": "", "column": ""}}, "optional": {"type": "boolean", "optional": true}, "defaultValue": {"type": "any", "optional": true}}, {"name": {"type": "string", "title": "Argument name"}, "type": {"enum": ["JsonbSchema"], "title": "Data type"}, "schema": {"title": "Jsonb schema", "oneOfType": [{"type": {"enum": ["boolean", "number", "integer", "string", "Date", "time", "timestamp", "any", "boolean[]", "number[]", "integer[]", "string[]", "Date[]", "time[]", "timestamp[]", "any[]"]}, "title": {"type": "string", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}, "defaultValue": {"type": "any", "optional": true}}, {"type": {"enum": ["object", "object[]"]}, "title": {"type": "string", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "optional": {"type": "boolean", "optional": true}, "properties": {"record": {"values": {"type": {"type": {"enum": ["boolean", "number", "integer", "string", "Date", "time", "timestamp", "any", "boolean[]", "number[]", "integer[]", "string[]", "Date[]", "time[]", "timestamp[]", "any[]"]}, "title": {"type": "string", "optional": true}, "nullable": {"type": "boolean", "optional": true}, "optional": {"type": "boolean", "optional": true}, "description": {"type": "string", "optional": true}, "defaultValue": {"type": "any", "optional": true}}}}}, "description": {"type": "string", "optional": true}, "defaultValue": {"type": "any", "optional": true}}]}, "optional": {"type": "boolean", "optional": true}, "defaultValue": {"type": "any", "optional": true}}]}}, "defaultValue": "[]"}, "description": "TEXT NOT NULL DEFAULT 'Method description'", "outputTable": "TEXT", "connection_id": {"info": {"hint": "If null then connection was deleted"}, "sqlDefinition": "UUID REFERENCES connections(id) ON DELETE SET NULL"}}, "indexes": {"unique_name": {"unique": true, "columns": "connection_id, name"}}}, "database_config_logs": {"columns": {"id": "SERIAL PRIMARY KEY REFERENCES database_configs (id) ON DELETE CASCADE", "on_run_logs": {"info": {"hint": "On mount logs"}, "sqlDefinition": "TEXT"}, "on_mount_logs": {"info": {"hint": "On mount logs"}, "sqlDefinition": "TEXT"}, "table_config_logs": {"info": {"hint": "On mount logs"}, "sqlDefinition": "TEXT"}}}, "access_control_methods": {"columns": {"access_control_id": "INTEGER NOT NULL REFERENCES access_control  ON DELETE CASCADE", "published_method_id": "INTEGER NOT NULL REFERENCES published_methods  ON DELETE CASCADE"}, "constraints": {"pkey": {"type": "PRIMARY KEY", "content": "published_method_id, access_control_id"}}}, "workspace_publish_modes": {"isLookupTable": {"values": {"fixed": {"en": "Fixed", "description": "The workspace layout is fixed"}, "editable": {"en": "Editable", "description": "The workspace will be cloned layout for each user"}}}}, "access_control_user_types": {"columns": {"user_type": "TEXT NOT NULL REFERENCES user_types(id)  ON DELETE CASCADE", "access_control_id": "INTEGER NOT NULL REFERENCES access_control(id)  ON DELETE CASCADE"}, "constraints": {"NoDupes": "UNIQUE(access_control_id, user_type)"}}, "access_control_allowed_llm": {"columns": {"llm_prompt_id": "INTEGER NOT NULL REFERENCES llm_prompts(id)", "access_control_id": "INTEGER NOT NULL REFERENCES access_control(id)", "llm_credential_id": "INTEGER NOT NULL REFERENCES llm_credentials(id)"}, "indexes": {"unique": {"unique": true, "columns": "access_control_id, llm_credential_id, llm_prompt_id"}}}, "access_control_connections": {"columns": {"connection_id": "UUID NOT NULL REFERENCES connections(id) ON DELETE CASCADE", "access_control_id": "INTEGER NOT NULL REFERENCES access_control  ON DELETE CASCADE"}, "indexes": {"unique_connection_id": {"unique": true, "columns": "connection_id, access_control_id"}}}}
\.


--
-- Data for Name: session_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.session_types (id) FROM stdin;
web
api_token
mobile
\.


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.sessions (id, id_num, user_id, name, socket_id, user_type, is_mobile, is_connected, active, project_id, ip_address, type, user_agent, created, last_used, expires) FROM stdin;
5a36028545a75319c7a1edb85e52ff19cafc610fc30e1074ac2c6d560947178b041672ca17c2c3bf86265a1574064f35	2	135539d6-77e8-448e-9f03-4dbaa02000f2	\N	OiBScd1KzRbc6Z5QAAAB	admin	f	t	t	\N	::1	web	electron	2025-06-30 10:05:40.858365	2025-06-30 10:05:42.46	2066659540847
\.


--
-- Data for Name: stats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stats (connection_id, datid, datname, pid, usesysid, usename, application_name, client_addr, client_hostname, client_port, backend_start, xact_start, query_start, state_change, wait_event_type, wait_event, state, backend_xid, backend_xmin, query, backend_type, blocked_by, blocked_by_num, id_query_hash, cpu, mem, "memPretty", mhz, cmd) FROM stdin;
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	25888	10	postgres	prostgles aa9901e0-9a3c-4f60-83fe-0d68e3dfc354 	::1	\N	60229	2025-06-30 10:05:41.010262-06	\N	2025-06-30 10:05:41.0426	2025-06-30 10:05:41.042724-06	Client	ClientRead	idle	\N	\N	/* prostgles-server internal query used for subscriptions and schema hot reload */ \nLISTEN "prostgles_aa9901e0-9a3c-4f60-83fe-0d68e3dfc354"	client backend	{}	0	2c8c1a55a92e8a11b6ef501600edf1e5	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	16008	10	postgres	prostgles ed942de0-1f58-492f-aa49-aefe96869a90 	::1	\N	60260	2025-06-30 10:05:53.325326-06	\N	\N	2025-06-30 10:05:53.3452-06	Client	ClientRead	idle	\N	\N		client backend	{}	0	5e4a09c72949f70c2bab629d3baca2d8	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	19224	10	postgres	prostgles ed942de0-1f58-492f-aa49-aefe96869a90 	::1	\N	60262	2025-06-30 10:05:54.837304-06	\N	2025-06-30 10:05:54.862619	2025-06-30 10:05:54.862691-06	Client	ClientRead	idle	\N	\N	/* prostgles-server internal query used for subscriptions and schema hot reload */ \nLISTEN "prostgles_ed942de0-1f58-492f-aa49-aefe96869a90"	client backend	{}	0	95dfb24ebf6fbf96b8cd5cbba41c6800	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	17720	10	postgres	prostgles aa9901e0-9a3c-4f60-83fe-0d68e3dfc354 	::1	\N	60303	2025-06-30 10:07:11.875496-06	\N	2025-06-30 10:07:34.067038	2025-06-30 10:07:34.068683-06	Client	ClientRead	idle	\N	\N	commit	client backend	{}	0	f5268e8925d6e4d01100954d2d62e976	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	5	postgres	18780	10	postgres	pgAdmin 4 - DB:postgres	::1	\N	53188	2025-06-30 09:21:32.54244-06	\N	2025-06-30 09:21:54.832334	2025-06-30 09:21:54.838752-06	Client	ClientRead	idle	\N	\N	/*pga4dash*/\nSELECT 'session_stats' AS chart_name, pg_catalog.row_to_json(t) AS chart_data\nFROM (SELECT\n   (SELECT count(*) FROM pg_catalog.pg_stat_activity) AS "Total",\n   (SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE state = 'active')  AS "Active",\n   (SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE state = 'idle')  AS "Idle"\n) t\nUNION ALL\nSELECT 'tps_stats' AS chart_name, pg_catalog.row_to_json(t) AS chart_data\nFROM (SELECT\n   (SELECT sum(xact_commit) + sum(xact_rollback) FROM pg_catalog.pg_stat_database) AS "Transactions",\n   (SELECT sum(xact_commit) FROM pg_catalog.pg_stat_database) AS "Commits",\n   (SELECT sum(xact_rollback) FROM pg_catalog.pg_stat_database) AS "Rollbacks"\n) t\nUNION ALL\nSELECT 'ti_stats' AS chart_name, pg_catalog.row_to_json(t) AS chart_data\nFROM (SELECT\n   (SELECT sum(tup_inserted) FROM pg_catalog.pg_stat_database) AS "Inserts",\n   (SELECT sum(tup_updated) FROM pg_catalog.pg_stat_database) AS "Updates",\n   (SELECT sum(tup_deleted) FROM pg_catalog.pg_stat_database) AS 	client backend	{}	0	9f4b571a17c70a01ca910c56cc072b81	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	23428	10	postgres	pgAdmin 4 - DB:Escaner	::1	\N	53202	2025-06-30 09:21:32.964981-06	\N	2025-06-30 10:07:33.046189	2025-06-30 10:07:33.060095-06	Client	ClientRead	idle	\N	\N	/*pga4dash*/\nSELECT 'session_stats' AS chart_name, pg_catalog.row_to_json(t) AS chart_data\nFROM (SELECT\n   (SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE datname = (SELECT datname FROM pg_catalog.pg_database WHERE oid = 16387)) AS "Total",\n   (SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE state = 'active' AND datname = (SELECT datname FROM pg_catalog.pg_database WHERE oid = 16387))  AS "Active",\n   (SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE state = 'idle' AND datname = (SELECT datname FROM pg_catalog.pg_database WHERE oid = 16387))  AS "Idle"\n) t\nUNION ALL\nSELECT 'tps_stats' AS chart_name, pg_catalog.row_to_json(t) AS chart_data\nFROM (SELECT\n   (SELECT sum(xact_commit) + sum(xact_rollback) FROM pg_catalog.pg_stat_database WHERE datname = (SELECT datname FROM pg_catalog.pg_database WHERE oid = 16387)) AS "Transactions",\n   (SELECT sum(xact_commit) FROM pg_catalog.pg_stat_database WHERE datname = (SELECT datname FROM pg_catalog.pg_database WHERE oid = 16387)) AS "Commits",\n   (SE	client backend	{}	0	208004cbd2409d8c89a7f54c2f853a8e	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	3704	10	postgres	pgAdmin 4 - CONN:7140273	::1	\N	53404	2025-06-30 09:22:19.812322-06	\N	2025-06-30 09:33:36.859819	2025-06-30 09:33:36.85989-06	Client	ClientRead	idle	\N	\N	SELECT oid, pg_catalog.format_type(oid, NULL) AS typname FROM pg_catalog.pg_type WHERE oid = ANY($1) ORDER BY oid;	client backend	{}	0	aee6bfd972f1ce37b5764ddb782eae2c	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	16387	Escaner	16756	10	postgres	prostgles aa9901e0-9a3c-4f60-83fe-0d68e3dfc354 	::1	\N	60224	2025-06-30 10:05:38.876258-06	\N	\N	2025-06-30 10:05:38.898603-06	Client	ClientRead	idle	\N	\N		client backend	{}	0	a5460fe6c23289fddcfe66efe033ae08	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	\N	\N	7776	\N	\N		\N	\N	\N	2025-06-27 15:10:09.902198-06	\N	\N	\N	Activity	AutovacuumMain	\N	\N	\N		autovacuum launcher	{}	0	23529b09a37f0a0c1e11e01d8619b93a	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	\N	\N	7276	10	postgres		\N	\N	\N	2025-06-27 15:10:09.905553-06	\N	\N	\N	Activity	LogicalLauncherMain	\N	\N	\N		logical replication launcher	{}	0	f7b027d45fd7484f6d0833823b98907e	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	\N	\N	9128	\N	\N		\N	\N	\N	2025-06-27 15:10:09.824586-06	\N	\N	\N	Activity	CheckpointerMain	\N	\N	\N		checkpointer	{}	0	35ec253885cf090f80881b44180afb00	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	\N	\N	9148	\N	\N		\N	\N	\N	2025-06-27 15:10:09.834697-06	\N	\N	\N	Activity	BgwriterHibernate	\N	\N	\N		background writer	{}	0	aad5adc307c4dd7e457509423a7f3734	\N	\N	\N	\N	\N
98b20426-f01b-4186-bde2-6b426b14e0c1	\N	\N	7132	\N	\N		\N	\N	\N	2025-06-27 15:10:09.894746-06	\N	\N	\N	Activity	WalWriterMain	\N	\N	\N		walwriter	{}	0	32b127307a606effdcc8e51f60a45922	\N	\N	\N	\N	\N
\.


--
-- Data for Name: user_statuses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_statuses (id) FROM stdin;
active
disabled
\.


--
-- Data for Name: user_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_types (id, en) FROM stdin;
admin	Highest access level
public	Public user. Account created on login and deleted on logout
default	\N
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, status, username, name, email, registration, auth_provider, auth_provider_user_id, auth_provider_profile, password, type, passwordless_admin, created, last_updated, options, "2fa") FROM stdin;
135539d6-77e8-448e-9f03-4dbaa02000f2	active	passwordless_admin	\N	\N	\N	\N	\N	\N		admin	t	2025-06-30 10:04:03.380418	1751299443380	\N	\N
\.


--
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuarios (id, usuario, "contrase├▒a", rol, fecha_creacion, activo, ultimo_acceso) FROM stdin;
1	admin	240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9	admin	2025-06-28 12:04:39.328707	t	2025-07-14 12:49:31.013316
245	paco	8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92	captura	2025-07-04 10:45:37.008837	t	\N
18	superadmin	4d883c9bd7eaabb9aa14af958386a41591feb1ccd55802c71af496d7a633193c	superadmin	2025-06-30 10:37:32.478881	t	2025-07-07 15:52:01.794618
\.


--
-- Data for Name: versiones; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.versiones (id, version, fecha_lanzamiento, descripcion, url_descarga, obligatoria, activa) FROM stdin;
\.


--
-- Data for Name: windows; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.windows (id, parent_window_id, user_id, workspace_id, type, table_name, method_name, table_oid, sql, selected_sql, name, "limit", closed, deleted, show_menu, minimised, fullscreen, sort, filter, "having", options, function_options, sql_options, columns, nested_tables, created, last_updated) FROM stdin;
85f76493-ab26-4a09-abfd-593d9758c82a	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	table	codigos_items	\N	16623			codigos_items - 1191 records	1000	f	f	f	f	f	[]	[]	[]	{"refresh": {"type": "Realtime", "intervalSeconds": 1, "throttleSeconds": 1}, "showFilters": false, "maxCellChars": 500}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	[{"name": "id", "show": true, "computed": false}, {"name": "codigo_barras", "show": true, "computed": false}, {"name": "item", "show": true, "computed": false}, {"name": "resultado", "show": true, "computed": false}, {"name": "fecha_creacion", "show": true, "computed": false}, {"name": "fecha_actualizacion", "show": true, "computed": false}]	\N	2025-06-30 10:04:20.070275	1751299460213
932645c4-ade2-4fad-ac4a-6f1b91e39df6	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	table	schema_version	\N	16697			schema_version	1000	f	f	f	f	f	[]	[]	[]	{"refresh": {"type": "Realtime", "intervalSeconds": 1, "throttleSeconds": 1}, "showFilters": false, "maxCellChars": 500}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	\N	\N	2025-06-30 10:04:26.474761	1751299466477
99f07478-5e12-4315-97d9-506c545e21b2	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	table	schema_version	\N	16697			schema_version	1000	f	f	f	f	f	[]	[]	[]	{"refresh": {"type": "Realtime", "intervalSeconds": 1, "throttleSeconds": 1}, "showFilters": false, "maxCellChars": 500}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	\N	\N	2025-06-30 10:04:27.604548	1751299467606
ece8d0e9-57d2-4f72-904a-53c951209500	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	table	users	\N	16754			users	1000	f	f	f	f	f	[]	[]	[]	{"refresh": {"type": "Realtime", "intervalSeconds": 1, "throttleSeconds": 1}, "showFilters": false, "maxCellChars": 500}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	\N	\N	2025-06-30 10:04:30.064687	1751299470065
d869861f-76c8-4381-864d-4c1d2bde3c81	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	sql	\N	\N	\N			SQL Query	1000	f	f	f	f	f	[]	[]	[]	{"hideTable": true}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	\N	\N	2025-06-30 10:04:34.519687	1751299474523
9bb2bd84-5be8-4c85-9476-f80a971eb790	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	table	global_settings	\N	17174			global_settings - 1 records	1000	f	f	f	f	f	[]	[]	[]	{"refresh": {"type": "Realtime", "intervalSeconds": 1, "throttleSeconds": 1}, "showFilters": false, "maxCellChars": 500}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	[{"name": "id", "show": true, "computed": false}, {"name": "allowed_origin", "show": true, "computed": false}, {"name": "allowed_ips", "show": true, "computed": false}, {"name": "allowed_ips_enabled", "show": true, "computed": false}, {"name": "trust_proxy", "show": true, "computed": false}, {"name": "enable_logs", "show": true, "computed": false}, {"name": "session_max_age_days", "show": true, "computed": false}, {"name": "magic_link_validity_days", "show": true, "computed": false}, {"name": "updated_by", "show": true, "computed": false}, {"name": "updated_at", "show": true, "computed": false}, {"name": "pass_process_env_vars_to_server_side_functions", "show": true, "computed": false}, {"name": "login_rate_limit_enabled", "show": true, "computed": false}, {"name": "login_rate_limit", "show": true, "computed": false}, {"name": "auth_providers", "show": true, "computed": false}, {"name": "tableConfig", "show": true, "computed": false}, {"name": "prostgles_registration", "show": true, "computed": false}]	\N	2025-06-30 10:04:24.560143	1751299556080
4da5fb73-9c1a-405b-be0d-949cebbc08a8	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	table	user_statuses	\N	16711			user_statuses	1000	f	f	f	f	f	[]	[]	[]	{"refresh": {"type": "Realtime", "intervalSeconds": 1, "throttleSeconds": 1}, "showFilters": false, "maxCellChars": 500}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	\N	\N	2025-06-30 10:06:06.152408	1751299566162
613552b7-d56a-4956-8275-22c348a6d8ed	\N	135539d6-77e8-448e-9f03-4dbaa02000f2	45d6e9f5-b805-4151-ac68-dd5e1494a326	sql	\N	\N	\N			SQL Query	1000	f	f	f	f	f	[]	[]	[]	{"hideTable": true}	\N	{"tabSize": 2, "executeOptions": "block", "errorMessageDisplay": "both"}	\N	\N	2025-06-30 10:06:45.667778	1751299605676
\.


--
-- Data for Name: workspace_publish_modes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.workspace_publish_modes (id, en, description) FROM stdin;
fixed	Fixed	The workspace layout is fixed
editable	Editable	The workspace will be cloned layout for each user
\.


--
-- Data for Name: workspaces; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.workspaces (id, user_id, connection_id, name, created, active_row, layout, icon, options, last_updated, last_used, deleted, url_path, parent_workspace_id, published, publish_mode) FROM stdin;
45d6e9f5-b805-4151-ac68-dd5e1494a326	135539d6-77e8-448e-9f03-4dbaa02000f2	98b20426-f01b-4186-bde2-6b426b14e0c1	default	2025-06-30 10:04:17.02433	{}	{"id": "1", "size": 100, "type": "tab", "items": [{"id": "9bb2bd84-5be8-4c85-9476-f80a971eb790", "size": 4, "type": "item", "title": "global_settings", "tableName": "global_settings"}, {"id": "932645c4-ade2-4fad-ac4a-6f1b91e39df6", "size": 4, "type": "item", "title": "schema_version", "tableName": "schema_version"}, {"id": "99f07478-5e12-4315-97d9-506c545e21b2", "size": 4, "type": "item", "title": "schema_version", "tableName": "schema_version"}, {"id": "ece8d0e9-57d2-4f72-904a-53c951209500", "size": 4, "type": "item", "title": "users", "tableName": "users"}, {"id": "d869861f-76c8-4381-864d-4c1d2bde3c81", "size": 4, "type": "item", "title": "SQL Query", "tableName": null}, {"id": "85f76493-ab26-4a09-abfd-593d9758c82a", "size": 20, "type": "item", "title": "codigos_items", "tableName": "codigos_items"}], "activeTabKey": "9bb2bd84-5be8-4c85-9476-f80a971eb790"}	\N	{"hideCounts": false, "pinnedMenu": true, "pinnedMenuWidth": 467, "tableListSortBy": "extraInfo", "tableListEndInfo": "size", "defaultLayoutType": "tab"}	1751299555951	2025-06-30 16:05:55.273	f	\N	\N	f	\N
\.


--
-- Name: access_control_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.access_control_id_seq', 1, false);


--
-- Name: alert_viewed_by_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.alert_viewed_by_id_seq', 1, false);


--
-- Name: alerts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.alerts_id_seq', 1, false);


--
-- Name: capturas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.capturas_id_seq', 19, true);


--
-- Name: clp_carga_detalle_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clp_carga_detalle_id_seq', 1231, true);


--
-- Name: clp_cargas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clp_cargas_id_seq', 7, true);


--
-- Name: codigos_barras_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.codigos_barras_id_seq', 3503, true);


--
-- Name: codigos_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.codigos_items_id_seq', 1, false);


--
-- Name: configuracion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.configuracion_id_seq', 449, true);


--
-- Name: consultas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.consultas_id_seq', 20, true);


--
-- Name: credentials_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.credentials_id_seq', 1, false);


--
-- Name: database_config_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.database_config_logs_id_seq', 1, false);


--
-- Name: database_configs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.database_configs_id_seq', 1, true);


--
-- Name: global_settings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.global_settings_id_seq', 1, true);


--
-- Name: historico_capturas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.historico_capturas_id_seq', 1, false);


--
-- Name: items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.items_id_seq', 4216, true);


--
-- Name: llm_chats_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.llm_chats_id_seq', 1, false);


--
-- Name: llm_credentials_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.llm_credentials_id_seq', 1, false);


--
-- Name: llm_messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.llm_messages_id_seq', 1, false);


--
-- Name: llm_prompts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.llm_prompts_id_seq', 2, true);


--
-- Name: login_attempts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.login_attempts_id_seq', 1, false);


--
-- Name: logs_aplicacion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.logs_aplicacion_id_seq', 2, true);


--
-- Name: logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.logs_id_seq', 1, false);


--
-- Name: published_methods_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.published_methods_id_seq', 1, false);


--
-- Name: sessions_id_num_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.sessions_id_num_seq', 2, true);


--
-- Name: usuarios_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuarios_id_seq', 429, true);


--
-- Name: versiones_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.versiones_id_seq', 1, false);


--
-- Name: app_triggers app_triggers_pkey; Type: CONSTRAINT; Schema: prostgles; Owner: postgres
--

ALTER TABLE ONLY prostgles.app_triggers
    ADD CONSTRAINT app_triggers_pkey PRIMARY KEY (app_id, table_name, condition_hash);


--
-- Name: apps apps_pkey; Type: CONSTRAINT; Schema: prostgles; Owner: postgres
--

ALTER TABLE ONLY prostgles.apps
    ADD CONSTRAINT apps_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: prostgles; Owner: postgres
--

ALTER TABLE ONLY prostgles.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (version);


--
-- Name: access_control_user_types NoDupes; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_user_types
    ADD CONSTRAINT "NoDupes" UNIQUE (access_control_id, user_type);


--
-- Name: access_control access_control_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control
    ADD CONSTRAINT access_control_pkey PRIMARY KEY (id);


--
-- Name: alert_viewed_by alert_viewed_by_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alert_viewed_by
    ADD CONSTRAINT alert_viewed_by_pkey PRIMARY KEY (id);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: backups backups_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT backups_pkey PRIMARY KEY (id);


--
-- Name: capturas capturas_codigo_item_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.capturas
    ADD CONSTRAINT capturas_codigo_item_key UNIQUE (codigo, item);


--
-- Name: capturas capturas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.capturas
    ADD CONSTRAINT capturas_pkey PRIMARY KEY (id);


--
-- Name: clp_carga_detalle clp_carga_detalle_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clp_carga_detalle
    ADD CONSTRAINT clp_carga_detalle_pkey PRIMARY KEY (id);


--
-- Name: clp_cargas clp_cargas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clp_cargas
    ADD CONSTRAINT clp_cargas_pkey PRIMARY KEY (id);


--
-- Name: codigos_barras codigos_barras_codigo_barras_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_barras
    ADD CONSTRAINT codigos_barras_codigo_barras_key UNIQUE (codigo_barras);


--
-- Name: codigos_barras codigos_barras_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_barras
    ADD CONSTRAINT codigos_barras_pkey PRIMARY KEY (id);


--
-- Name: codigos_items codigos_items_codigo_barras_item_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_items
    ADD CONSTRAINT codigos_items_codigo_barras_item_key UNIQUE (codigo_barras, item);


--
-- Name: codigos_items codigos_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_items
    ADD CONSTRAINT codigos_items_pkey PRIMARY KEY (id);


--
-- Name: configuracion configuracion_clave_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion
    ADD CONSTRAINT configuracion_clave_key UNIQUE (clave);


--
-- Name: configuracion configuracion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.configuracion
    ADD CONSTRAINT configuracion_pkey PRIMARY KEY (id);


--
-- Name: connections connections_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT connections_pkey PRIMARY KEY (id);


--
-- Name: consultas consultas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consultas
    ADD CONSTRAINT consultas_pkey PRIMARY KEY (id);


--
-- Name: credential_types credential_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credential_types
    ADD CONSTRAINT credential_types_pkey PRIMARY KEY (id);


--
-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (id);


--
-- Name: database_config_logs database_config_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_config_logs
    ADD CONSTRAINT database_config_logs_pkey PRIMARY KEY (id);


--
-- Name: database_configs database_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_configs
    ADD CONSTRAINT database_configs_pkey PRIMARY KEY (id);


--
-- Name: global_settings global_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.global_settings
    ADD CONSTRAINT global_settings_pkey PRIMARY KEY (id);


--
-- Name: historico_capturas historico_capturas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.historico_capturas
    ADD CONSTRAINT historico_capturas_pkey PRIMARY KEY (id);


--
-- Name: items items_item_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_item_key UNIQUE (item);


--
-- Name: items items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.items
    ADD CONSTRAINT items_pkey PRIMARY KEY (id);


--
-- Name: links links_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT links_pkey PRIMARY KEY (id);


--
-- Name: llm_chats llm_chats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_chats
    ADD CONSTRAINT llm_chats_pkey PRIMARY KEY (id);


--
-- Name: llm_credentials llm_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_credentials
    ADD CONSTRAINT llm_credentials_pkey PRIMARY KEY (id);


--
-- Name: llm_messages llm_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_messages
    ADD CONSTRAINT llm_messages_pkey PRIMARY KEY (id);


--
-- Name: llm_prompts llm_prompts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_prompts
    ADD CONSTRAINT llm_prompts_pkey PRIMARY KEY (id);


--
-- Name: login_attempts login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (id);


--
-- Name: logs_aplicacion logs_aplicacion_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.logs_aplicacion
    ADD CONSTRAINT logs_aplicacion_pkey PRIMARY KEY (id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: magic_links magic_links_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.magic_links
    ADD CONSTRAINT magic_links_pkey PRIMARY KEY (id);


--
-- Name: access_control_methods pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_methods
    ADD CONSTRAINT pkey PRIMARY KEY (published_method_id, access_control_id);


--
-- Name: published_methods published_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.published_methods
    ADD CONSTRAINT published_methods_pkey PRIMARY KEY (id);


--
-- Name: schema_version schema_version_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_pkey PRIMARY KEY (id);


--
-- Name: session_types session_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.session_types
    ADD CONSTRAINT session_types_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_id_key UNIQUE (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id_num);


--
-- Name: stats stats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stats
    ADD CONSTRAINT stats_pkey PRIMARY KEY (pid, connection_id);


--
-- Name: connections uniqueConName; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT "uniqueConName" UNIQUE (name, user_id);


--
-- Name: database_configs uniqueDatabase; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_configs
    ADD CONSTRAINT "uniqueDatabase" UNIQUE (db_name, db_host, db_port);


--
-- Name: connections unique_connection_url_path; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT unique_connection_url_path UNIQUE (url_path);


--
-- Name: workspaces unique_name_per_user_perCon; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT "unique_name_per_user_perCon" UNIQUE (connection_id, user_id, name);


--
-- Name: workspaces unique_url_path; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT unique_url_path UNIQUE (url_path);


--
-- Name: user_statuses user_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_statuses
    ADD CONSTRAINT user_statuses_pkey PRIMARY KEY (id);


--
-- Name: user_types user_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_types
    ADD CONSTRAINT user_types_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id);


--
-- Name: usuarios usuarios_usuario_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_usuario_key UNIQUE (usuario);


--
-- Name: versiones versiones_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.versiones
    ADD CONSTRAINT versiones_pkey PRIMARY KEY (id);


--
-- Name: windows windows_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.windows
    ADD CONSTRAINT windows_pkey PRIMARY KEY (id);


--
-- Name: workspace_publish_modes workspace_publish_modes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspace_publish_modes
    ADD CONSTRAINT workspace_publish_modes_pkey PRIMARY KEY (id);


--
-- Name: workspaces workspaces_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_pkey PRIMARY KEY (id);


--
-- Name: Only one passwordless_admin admin account allowed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "Only one passwordless_admin admin account allowed" ON public.users USING btree (passwordless_admin) WHERE (passwordless_admin = true);


--
-- Name: idx_clp_carga_detalle_carga; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_clp_carga_detalle_carga ON public.clp_carga_detalle USING btree (clp_carga_id);


--
-- Name: idx_codigos_barras_codigo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_codigos_barras_codigo ON public.codigos_barras USING btree (codigo_barras);


--
-- Name: idx_consultas_usuario_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_consultas_usuario_fecha ON public.consultas USING btree (usuario, fecha_hora);


--
-- Name: idx_items_item; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX idx_items_item ON public.items USING btree (item);


--
-- Name: unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "unique" ON public.access_control_allowed_llm USING btree (access_control_id, llm_credential_id, llm_prompt_id);


--
-- Name: unique_connection_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_connection_id ON public.access_control_connections USING btree (connection_id, access_control_id);


--
-- Name: unique_default; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_default ON public.llm_credentials USING btree (is_default) WHERE (is_default = true);


--
-- Name: unique_llm_credential_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_llm_credential_name ON public.llm_credentials USING btree (name, user_id);


--
-- Name: unique_llm_prompt_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_llm_prompt_name ON public.llm_prompts USING btree (name, user_id);


--
-- Name: unique_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unique_name ON public.published_methods USING btree (connection_id, name);


--
-- Name: app_triggers prostgles_triggers_delete; Type: TRIGGER; Schema: prostgles; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_delete AFTER DELETE ON prostgles.app_triggers REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.trigger_add_remove_func();


--
-- Name: app_triggers prostgles_triggers_insert; Type: TRIGGER; Schema: prostgles; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_insert AFTER INSERT ON prostgles.app_triggers REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.trigger_add_remove_func();


--
-- Name: global_settings Update updated_at_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "Update updated_at_update" BEFORE UPDATE ON public.global_settings FOR EACH ROW EXECUTE FUNCTION public."Update updated_at"();


--
-- Name: users atLeastOneActiveAdmin_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "atLeastOneActiveAdmin_delete" AFTER DELETE ON public.users REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION public."atLeastOneActiveAdmin"();


--
-- Name: users atLeastOneActiveAdmin_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "atLeastOneActiveAdmin_update" AFTER UPDATE ON public.users REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION public."atLeastOneActiveAdmin"();


--
-- Name: user_types atLeastOneAdminAndPublic_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "atLeastOneAdminAndPublic_delete" AFTER DELETE ON public.user_types REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION public."atLeastOneAdminAndPublic"();


--
-- Name: user_types atLeastOneAdminAndPublic_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "atLeastOneAdminAndPublic_update" AFTER UPDATE ON public.user_types REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION public."atLeastOneAdminAndPublic"();


--
-- Name: access_control prostgles_triggers_access_control_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_delete AFTER DELETE ON public.access_control REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control prostgles_triggers_access_control_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_insert AFTER INSERT ON public.access_control REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_methods prostgles_triggers_access_control_methods_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_methods_delete AFTER DELETE ON public.access_control_methods REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_methods prostgles_triggers_access_control_methods_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_methods_insert AFTER INSERT ON public.access_control_methods REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_methods prostgles_triggers_access_control_methods_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_methods_update AFTER UPDATE ON public.access_control_methods REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control prostgles_triggers_access_control_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_update AFTER UPDATE ON public.access_control REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_user_types prostgles_triggers_access_control_user_types_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_user_types_delete AFTER DELETE ON public.access_control_user_types REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_user_types prostgles_triggers_access_control_user_types_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_user_types_insert AFTER INSERT ON public.access_control_user_types REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_user_types prostgles_triggers_access_control_user_types_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_access_control_user_types_update AFTER UPDATE ON public.access_control_user_types REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: alert_viewed_by prostgles_triggers_alert_viewed_by_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_alert_viewed_by_delete AFTER DELETE ON public.alert_viewed_by REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: alert_viewed_by prostgles_triggers_alert_viewed_by_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_alert_viewed_by_insert AFTER INSERT ON public.alert_viewed_by REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: alert_viewed_by prostgles_triggers_alert_viewed_by_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_alert_viewed_by_update AFTER UPDATE ON public.alert_viewed_by REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: alerts prostgles_triggers_alerts_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_alerts_delete AFTER DELETE ON public.alerts REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: alerts prostgles_triggers_alerts_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_alerts_insert AFTER INSERT ON public.alerts REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: alerts prostgles_triggers_alerts_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_alerts_update AFTER UPDATE ON public.alerts REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: connections prostgles_triggers_connections_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_connections_delete AFTER DELETE ON public.connections REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: connections prostgles_triggers_connections_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_connections_insert AFTER INSERT ON public.connections REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: connections prostgles_triggers_connections_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_connections_update AFTER UPDATE ON public.connections REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: database_configs prostgles_triggers_database_configs_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_database_configs_delete AFTER DELETE ON public.database_configs REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: database_configs prostgles_triggers_database_configs_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_database_configs_insert AFTER INSERT ON public.database_configs REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: database_configs prostgles_triggers_database_configs_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_database_configs_update AFTER UPDATE ON public.database_configs REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: global_settings prostgles_triggers_global_settings_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_global_settings_delete AFTER DELETE ON public.global_settings REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: global_settings prostgles_triggers_global_settings_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_global_settings_insert AFTER INSERT ON public.global_settings REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: global_settings prostgles_triggers_global_settings_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_global_settings_update AFTER UPDATE ON public.global_settings REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: links prostgles_triggers_links_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_links_delete AFTER DELETE ON public.links REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: links prostgles_triggers_links_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_links_insert AFTER INSERT ON public.links REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: links prostgles_triggers_links_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_links_update AFTER UPDATE ON public.links REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: llm_credentials prostgles_triggers_llm_credentials_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_llm_credentials_delete AFTER DELETE ON public.llm_credentials REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: llm_credentials prostgles_triggers_llm_credentials_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_llm_credentials_insert AFTER INSERT ON public.llm_credentials REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: llm_credentials prostgles_triggers_llm_credentials_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_llm_credentials_update AFTER UPDATE ON public.llm_credentials REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: llm_prompts prostgles_triggers_llm_prompts_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_llm_prompts_delete AFTER DELETE ON public.llm_prompts REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: llm_prompts prostgles_triggers_llm_prompts_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_llm_prompts_insert AFTER INSERT ON public.llm_prompts REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: llm_prompts prostgles_triggers_llm_prompts_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_llm_prompts_update AFTER UPDATE ON public.llm_prompts REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: stats prostgles_triggers_stats_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_stats_delete AFTER DELETE ON public.stats REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: stats prostgles_triggers_stats_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_stats_insert AFTER INSERT ON public.stats REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: stats prostgles_triggers_stats_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_stats_update AFTER UPDATE ON public.stats REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: users prostgles_triggers_users_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_users_delete AFTER DELETE ON public.users REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: users prostgles_triggers_users_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_users_insert AFTER INSERT ON public.users REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: users prostgles_triggers_users_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_users_update AFTER UPDATE ON public.users REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: windows prostgles_triggers_windows_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_windows_delete AFTER DELETE ON public.windows REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: windows prostgles_triggers_windows_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_windows_insert AFTER INSERT ON public.windows REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: windows prostgles_triggers_windows_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_windows_update AFTER UPDATE ON public.windows REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: workspaces prostgles_triggers_workspaces_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_workspaces_delete AFTER DELETE ON public.workspaces REFERENCING OLD TABLE AS old_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: workspaces prostgles_triggers_workspaces_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_workspaces_insert AFTER INSERT ON public.workspaces REFERENCING NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: workspaces prostgles_triggers_workspaces_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER prostgles_triggers_workspaces_update AFTER UPDATE ON public.workspaces REFERENCING OLD TABLE AS old_table NEW TABLE AS new_table FOR EACH STATEMENT EXECUTE FUNCTION prostgles.prostgles_trigger_function();


--
-- Name: access_control_allowed_llm access_control_allowed_llm_access_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_allowed_llm
    ADD CONSTRAINT access_control_allowed_llm_access_control_id_fkey FOREIGN KEY (access_control_id) REFERENCES public.access_control(id);


--
-- Name: access_control_allowed_llm access_control_allowed_llm_llm_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_allowed_llm
    ADD CONSTRAINT access_control_allowed_llm_llm_credential_id_fkey FOREIGN KEY (llm_credential_id) REFERENCES public.llm_credentials(id);


--
-- Name: access_control_allowed_llm access_control_allowed_llm_llm_prompt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_allowed_llm
    ADD CONSTRAINT access_control_allowed_llm_llm_prompt_id_fkey FOREIGN KEY (llm_prompt_id) REFERENCES public.llm_prompts(id);


--
-- Name: access_control_connections access_control_connections_access_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_connections
    ADD CONSTRAINT access_control_connections_access_control_id_fkey FOREIGN KEY (access_control_id) REFERENCES public.access_control(id) ON DELETE CASCADE;


--
-- Name: access_control_connections access_control_connections_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_connections
    ADD CONSTRAINT access_control_connections_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES public.connections(id) ON DELETE CASCADE;


--
-- Name: access_control access_control_database_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control
    ADD CONSTRAINT access_control_database_id_fkey FOREIGN KEY (database_id) REFERENCES public.database_configs(id) ON DELETE CASCADE;


--
-- Name: access_control_methods access_control_methods_access_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_methods
    ADD CONSTRAINT access_control_methods_access_control_id_fkey FOREIGN KEY (access_control_id) REFERENCES public.access_control(id) ON DELETE CASCADE;


--
-- Name: access_control_methods access_control_methods_published_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_methods
    ADD CONSTRAINT access_control_methods_published_method_id_fkey FOREIGN KEY (published_method_id) REFERENCES public.published_methods(id) ON DELETE CASCADE;


--
-- Name: access_control_user_types access_control_user_types_access_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_user_types
    ADD CONSTRAINT access_control_user_types_access_control_id_fkey FOREIGN KEY (access_control_id) REFERENCES public.access_control(id) ON DELETE CASCADE;


--
-- Name: access_control_user_types access_control_user_types_user_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.access_control_user_types
    ADD CONSTRAINT access_control_user_types_user_type_fkey FOREIGN KEY (user_type) REFERENCES public.user_types(id) ON DELETE CASCADE;


--
-- Name: alert_viewed_by alert_viewed_by_alert_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alert_viewed_by
    ADD CONSTRAINT alert_viewed_by_alert_id_fkey FOREIGN KEY (alert_id) REFERENCES public.alerts(id) ON DELETE CASCADE;


--
-- Name: alert_viewed_by alert_viewed_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alert_viewed_by
    ADD CONSTRAINT alert_viewed_by_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: alerts alerts_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES public.connections(id) ON DELETE SET NULL;


--
-- Name: alerts alerts_database_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_database_config_id_fkey FOREIGN KEY (database_config_id) REFERENCES public.database_configs(id) ON DELETE SET NULL;


--
-- Name: backups backups_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT backups_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES public.connections(id) ON DELETE SET NULL;


--
-- Name: backups backups_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT backups_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.credentials(id);


--
-- Name: clp_carga_detalle clp_carga_detalle_clp_carga_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clp_carga_detalle
    ADD CONSTRAINT clp_carga_detalle_clp_carga_id_fkey FOREIGN KEY (clp_carga_id) REFERENCES public.clp_cargas(id) ON DELETE CASCADE;


--
-- Name: clp_carga_detalle clp_carga_detalle_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clp_carga_detalle
    ADD CONSTRAINT clp_carga_detalle_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id) ON DELETE CASCADE;


--
-- Name: codigos_barras codigos_barras_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.codigos_barras
    ADD CONSTRAINT codigos_barras_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.items(id);


--
-- Name: connections connections_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: credentials credentials_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_type_fkey FOREIGN KEY (type) REFERENCES public.credential_types(id);


--
-- Name: credentials credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: connections database_config_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.connections
    ADD CONSTRAINT database_config_fkey FOREIGN KEY (db_name, db_host, db_port) REFERENCES public.database_configs(db_name, db_host, db_port);


--
-- Name: database_config_logs database_config_logs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_config_logs
    ADD CONSTRAINT database_config_logs_id_fkey FOREIGN KEY (id) REFERENCES public.database_configs(id) ON DELETE CASCADE;


--
-- Name: database_stats database_stats_database_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.database_stats
    ADD CONSTRAINT database_stats_database_config_id_fkey FOREIGN KEY (database_config_id) REFERENCES public.database_configs(id) ON DELETE SET NULL;


--
-- Name: links links_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT links_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: links links_w1_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT links_w1_id_fkey FOREIGN KEY (w1_id) REFERENCES public.windows(id) ON DELETE CASCADE;


--
-- Name: links links_w2_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT links_w2_id_fkey FOREIGN KEY (w2_id) REFERENCES public.windows(id) ON DELETE CASCADE;


--
-- Name: links links_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.links
    ADD CONSTRAINT links_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL;


--
-- Name: llm_chats llm_chats_llm_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_chats
    ADD CONSTRAINT llm_chats_llm_credential_id_fkey FOREIGN KEY (llm_credential_id) REFERENCES public.llm_credentials(id) ON DELETE SET NULL;


--
-- Name: llm_chats llm_chats_llm_prompt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_chats
    ADD CONSTRAINT llm_chats_llm_prompt_id_fkey FOREIGN KEY (llm_prompt_id) REFERENCES public.llm_prompts(id) ON DELETE SET NULL;


--
-- Name: llm_chats llm_chats_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_chats
    ADD CONSTRAINT llm_chats_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: llm_credentials llm_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_credentials
    ADD CONSTRAINT llm_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: llm_messages llm_messages_chat_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_messages
    ADD CONSTRAINT llm_messages_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES public.llm_chats(id) ON DELETE CASCADE;


--
-- Name: llm_messages llm_messages_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_messages
    ADD CONSTRAINT llm_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: llm_prompts llm_prompts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.llm_prompts
    ADD CONSTRAINT llm_prompts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: magic_links magic_links_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.magic_links
    ADD CONSTRAINT magic_links_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: published_methods published_methods_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.published_methods
    ADD CONSTRAINT published_methods_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES public.connections(id) ON DELETE SET NULL;


--
-- Name: sessions sessions_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_type_fkey FOREIGN KEY (type) REFERENCES public.session_types(id);


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: stats stats_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stats
    ADD CONSTRAINT stats_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES public.connections(id) ON DELETE CASCADE;


--
-- Name: users users_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_status_fkey FOREIGN KEY (status) REFERENCES public.user_statuses(id);


--
-- Name: users users_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_type_fkey FOREIGN KEY (type) REFERENCES public.user_types(id);


--
-- Name: windows windows_parent_window_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.windows
    ADD CONSTRAINT windows_parent_window_id_fkey FOREIGN KEY (parent_window_id) REFERENCES public.windows(id) ON DELETE CASCADE;


--
-- Name: windows windows_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.windows
    ADD CONSTRAINT windows_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: windows windows_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.windows
    ADD CONSTRAINT windows_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL;


--
-- Name: workspaces workspaces_connection_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES public.connections(id) ON DELETE CASCADE;


--
-- Name: workspaces workspaces_parent_workspace_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_parent_workspace_id_fkey FOREIGN KEY (parent_workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL;


--
-- Name: workspaces workspaces_publish_mode_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_publish_mode_fkey FOREIGN KEY (publish_mode) REFERENCES public.workspace_publish_modes(id);


--
-- Name: workspaces workspaces_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.workspaces
    ADD CONSTRAINT workspaces_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: prostgles_schema_watch_trigger_new; Type: EVENT TRIGGER; Schema: -; Owner: postgres
--

CREATE EVENT TRIGGER prostgles_schema_watch_trigger_new ON ddl_command_end
         WHEN TAG IN ('ALTER AGGREGATE', 'ALTER COLLATION', 'ALTER CONVERSION', 'ALTER DOMAIN', 'ALTER DEFAULT PRIVILEGES', 'ALTER EXTENSION', 'ALTER FOREIGN DATA WRAPPER', 'ALTER FOREIGN TABLE', 'ALTER FUNCTION', 'ALTER LANGUAGE', 'ALTER LARGE OBJECT', 'ALTER MATERIALIZED VIEW', 'ALTER OPERATOR', 'ALTER OPERATOR CLASS', 'ALTER OPERATOR FAMILY', 'ALTER POLICY', 'ALTER PROCEDURE', 'ALTER PUBLICATION', 'ALTER ROUTINE', 'ALTER SCHEMA', 'ALTER SEQUENCE', 'ALTER SERVER', 'ALTER STATISTICS', 'ALTER SUBSCRIPTION', 'ALTER TABLE', 'ALTER TEXT SEARCH CONFIGURATION', 'ALTER TEXT SEARCH DICTIONARY', 'ALTER TEXT SEARCH PARSER', 'ALTER TEXT SEARCH TEMPLATE', 'ALTER TRIGGER', 'ALTER TYPE', 'ALTER USER MAPPING', 'ALTER VIEW', 'COMMENT', 'CREATE ACCESS METHOD', 'CREATE AGGREGATE', 'CREATE CAST', 'CREATE COLLATION', 'CREATE CONVERSION', 'CREATE DOMAIN', 'CREATE EXTENSION', 'CREATE FOREIGN DATA WRAPPER', 'CREATE FOREIGN TABLE', 'CREATE FUNCTION', 'CREATE INDEX', 'CREATE LANGUAGE', 'CREATE MATERIALIZED VIEW', 'CREATE OPERATOR', 'CREATE OPERATOR CLASS', 'CREATE OPERATOR FAMILY', 'CREATE POLICY', 'CREATE PROCEDURE', 'CREATE PUBLICATION', 'CREATE RULE', 'CREATE SCHEMA', 'CREATE SEQUENCE', 'CREATE SERVER', 'CREATE STATISTICS', 'CREATE SUBSCRIPTION', 'CREATE TABLE', 'CREATE TABLE AS', 'CREATE TEXT SEARCH CONFIGURATION', 'CREATE TEXT SEARCH DICTIONARY', 'CREATE TEXT SEARCH PARSER', 'CREATE TEXT SEARCH TEMPLATE', 'CREATE TRIGGER', 'CREATE TYPE', 'CREATE USER MAPPING', 'CREATE VIEW', 'DROP ACCESS METHOD', 'DROP AGGREGATE', 'DROP CAST', 'DROP COLLATION', 'DROP CONVERSION', 'DROP DOMAIN', 'DROP EXTENSION', 'DROP FOREIGN DATA WRAPPER', 'DROP FOREIGN TABLE', 'DROP FUNCTION', 'DROP INDEX', 'DROP LANGUAGE', 'DROP MATERIALIZED VIEW', 'DROP OPERATOR', 'DROP OPERATOR CLASS', 'DROP OPERATOR FAMILY', 'DROP OWNED', 'DROP POLICY', 'DROP PROCEDURE', 'DROP PUBLICATION', 'DROP ROUTINE', 'DROP RULE', 'DROP SCHEMA', 'DROP SEQUENCE', 'DROP SERVER', 'DROP STATISTICS', 'DROP SUBSCRIPTION', 'DROP TABLE', 'DROP TEXT SEARCH CONFIGURATION', 'DROP TEXT SEARCH DICTIONARY', 'DROP TEXT SEARCH PARSER', 'DROP TEXT SEARCH TEMPLATE', 'DROP TRIGGER', 'DROP TYPE', 'DROP USER MAPPING', 'DROP VIEW', 'GRANT', 'IMPORT FOREIGN SCHEMA', 'REFRESH MATERIALIZED VIEW', 'REVOKE', 'SECURITY LABEL', 'SELECT INTO')
   EXECUTE FUNCTION prostgles.schema_watch_func();


ALTER EVENT TRIGGER prostgles_schema_watch_trigger_new OWNER TO postgres;

--
-- Name: prostgles_schema_watch_trigger_new_drop; Type: EVENT TRIGGER; Schema: -; Owner: postgres
--

CREATE EVENT TRIGGER prostgles_schema_watch_trigger_new_drop ON sql_drop
   EXECUTE FUNCTION prostgles.schema_watch_func();


ALTER EVENT TRIGGER prostgles_schema_watch_trigger_new_drop OWNER TO postgres;

--
-- PostgreSQL database dump complete
--

