#!/bin/bash
#
# cron-rotate-agc-log
#     wrapper: rotate oracle table
#
#     must be executed on the first day of each month:
#         03 02 1 * * /path/cron-rotate-agc-log -p
#
# Marcus Vinicius Ferreira                      ferreira.mv[ at ]gmail.com
# 2009/Set
#

[ "$1" != "-p" ] && {
    echo
    echo "Usage: $0 -p [yyyy_mm]"
    echo
    echo "    rotate oracle table agc_adm.log"
    echo
    exit 1
}

# Subs
prev_month() {
perl -e '
    # current day/month/year
    my ($dd, $mm, $yy) = (localtime)[3,4,5];

    # first day of current month/year to epoch
    use Time::Local; #sec, min, hr, mday,  mm,  yy);
    $time = timelocal(  0,   0,  0,    1, $mm, $yy);

    # previous day, i.e., previous month
    $time -= 60 * 60 * 24 * 1 ; # 24h = 1d

    # epoch to my date
    use Time::localtime;
    $tm = localtime($time);
    printf("%04d_%02d\n", $tm->year+1900, $tm->mon+1);
'
}

log() {
# screen: add to log explicitly
#   cron: already sending to log
    if tty -s
    then echo "$( date '+%Y-%m-%d %X'): $1" >> $LOG
    else echo "$( date '+%Y-%m-%d %X'): $1"
    fi
}

email() {
    subject="$(hostname) - Rotate $OWNER $TABLE"
    mail -s "$subject - $1" $MAIL_TO <<MAIL
From: no-reply@oracle
To: $MAIL_TO
Subject: $subject - $1

Log: $LOG

$( cat -n $LOG | tail -15 )

MAIL
}

exists_table() {
cat > /tmp/$$.1.sql <<CAT
    WHENEVER SQLERROR EXIT FAILURE
    set echo on
    set feedback off
    set time off
    set timing off
    set serveroutput on

    DECLARE
        x                 NUMBER;
        already_exists    EXCEPTION;
    BEGIN
        FOR r IN (
            select 1
              from dba_objects
             where       owner=UPPER('$OWNER')
               and object_name=UPPER('$NEW_TABLE')
                 )
        LOOP
        --
            DBMS_OUTPUT.PUT_LINE('Table already exists.');
            RAISE already_exists;
        --
        END LOOP;
        --
        DBMS_OUTPUT.PUT_LINE('Table not found.');
        --
    EXCEPTION
        WHEN already_exists THEN
            RAISE_APPLICATION_ERROR(-20101, 'already_exists');
        WHEN OTHERS THEN RAISE;
    END;
/
CAT

sqlplus -L $sysdba <<SQL
    @/tmp/$$.1.sql
SQL

    err="$?"
    /bin/rm -f /tmp/$$.1.sql
    echo "Err [$?]"
    return $err
}

create_table() {
cat > /tmp/$$.1.sql <<CAT
    WHENEVER SQLERROR EXIT FAILURE
    set echo on
    set time on
    set timing on

    create table ${OWNER}.$NEW_TABLE
        tablespace $TBSPC_ROTATE
    as select /* create_table $0 */ *
         from ${OWNER}.$TABLE
        where $DT_COLUMN BETWEEN      TO_DATE( '$DT', 'YYYY_MM' )      -- result: first day, first hour
                         AND LAST_DAY(TO_DATE( '$DT', 'YYYY_MM' )) + 1 -- result: last day, last hour
    ;
CAT

sqlplus -L $sysdba <<SQL
    @/tmp/$$.1.sql
SQL

    err="$?"
    /bin/rm -f /tmp/$$.1.sql
    echo "Err [$?]"
    return $err
}

purge_data() {
cat > /tmp/$$.1.sql <<CAT
    WHENEVER SQLERROR EXIT FAILURE
    set echo on
    set time on
    set timing on

    BEGIN
      LOOP
        delete /* purge_data $0 */
          from ${OWNER}.$TABLE
         where $DT_COLUMN BETWEEN      TO_DATE( '$DT', 'YYYY_MM' )      -- result: first day, first hour
                          AND LAST_DAY(TO_DATE( '$DT', 'YYYY_MM' )) + 1 -- result: last day, last hour
           and rownum <= 100000
             ;
        EXIT when SQL%NOTFOUND;
        ---
        commit ;
        ---
      END LOOP;
      commit ;
    END;
/
CAT

sqlplus -L $sysdba <<SQL
    @/tmp/$$.1.sql
SQL

    err="$?"
    /bin/rm -f /tmp/$$.1.sql
    echo "Err [$?]"
    return $err
}

### Setup

. /u01/app/oracle/bin/env-ora.sh

# Log
[ -z $LOG_DIR ] && LOG_DIR=/tmp
LOG=${LOG_DIR}/${0##*/}.log
touch $LOG

### Output via cron
if ! tty -s
then exec 1>>$LOG
     exec 2>>$LOG
fi

#    exec 1>>$LOG
#    exec 2>>$LOG

# Auto-rotate
size=$( /bin/ls -l $LOG | awk '{print $5}' ) # size bytes
[ $size -gt 5242880 ] && > $LOG              # 5000k, 5m

echo "Using logfile [$LOG], $size bytes"

### Params
if [ -z "$2" ]
then DT=$( prev_month )
else DT="$2"
fi

       OWNER="agc_adm"
       TABLE="log"
   NEW_TABLE="agc_log_${DT}"
   DT_COLUMN="dat_log"
TBSPC_ROTATE="agc_log_data_rotate_01"

if [ -z "$SYSTEM" ]
then sysdba="/ as sysdba"
else sysdba="$SYSTEM"
fi

### Main

log "BEGIN"

### 1/3
log "Table [${OWNER}.${NEW_TABLE}]"

exists_table
if [ "$?" != "0" ]
then
    log "Table already exists. Exiting."
    email "Table already exists."
    exit 2
fi

### 2/3
log "Creating new table..."
if create_table
then log "Table created."
else
    log "Table error. Check your log."
    email "Table Error"
    exit 3
fi

### 3/3
log "Purging from [${OWNER}.${TABLE}]"
if purge_data
then
    log "Purge finished"
else
    log "Purge error. Check your log."
    email "Purge Error"
    exit 4
fi

log "END"
email "Success"
exit 0;

