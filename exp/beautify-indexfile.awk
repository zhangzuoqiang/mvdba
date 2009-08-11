#!/usr/bin/awk -f
# -----------------------------------------------------------------------------
# NAME
#   beautify_indexfile.awk
#   Ref: http://www.orafaq.com/wiki/Scripts#AWK_Scripts
#
# DESCRIPTION
#   If you have used 'imp INDEXFILE=' to extract the SQL from an export file,
#   you can use this script to seperate the create table and create index
#   commands into different files.
#
#   It also does some formatting to make it easier to do search/replace, such
#   as putting the STORAGE clause on a single line.
#
#   This version works with Oracle 9 index files.
#
#
# USAGE
#   awk -f beautify_indexfile.awk INDEXFILE
#   (produces files 'create_table.sql'; 'create_index.sql' and 'create_trash.sql'
#
#
# WARNING
#   It makes some assumptions about the format of the output file, but since
#   the file is generated by imp, I guess its not too much of a problem.
#
#
# WARNING
#   I have not tested it with Oracle 8+ features, such as IOTs.  Come to think
#   of it, I haven't tested it with clusters either.  Oh well, you've got the
#   source.  Modify it until it works.
#
#
# TIPS
#   1) If you have a POSIX compatible shell, you can run this script without
#      having to specify 'awk -f'.
#
#      First, make this file executable; change the very first like to a
#      hash '#', followed by an exclamation mark '!', followed by the path
#      to 'awk' on your system, followed by a space, followed by '-f'.
#
#      Then you can run this script like this:-
#         beautify_indexfile.awk INDEXFILE
#
#      Oh, you might want to rename this script to something shorter, such as 'pif'
#
#
# HISTORY
#   Revision 1.2  2004-07-21  22:02:00  tangt (TAK TANG)
#   Minor, unlisted tweaks to do with constraints.
#
#   Revision 1.1  2004-03-06  13:00:00  tangt (TAK TANG)
#   Initial version
#
#
# COPYRIGHT
#   Er, its free.  You reap what you sow.  Share and enjoy.
# -----------------------------------------------------------------------------

BEGIN {
  index_file="create_index.sql";
  print "REM Generated automatically" >index_file;
  print "SET TRIMSPOOL ON TIMING ON"  >index_file;
  print "ALTER SESSION SET SORT_AREA_SIZE=102400000;" >index_file;
  print "SPOOL create_index.log"      >index_file;
  print ""                            >index_file;

  table_file="create_table.sql";
  print "REM Generated automatically" >table_file;
  print "SET TRIMSPOOL ON TIMING ON"  >table_file;
  print "SPOOL create_table.log"      >table_file;
  print ""                            >table_file;

  trash_file="create_trash.sql";
  print "REM Generated automatically" >trash_file;

  current_file=trash_file;

  data="";
}

# -----------------------------------------------------------------------------

/^REM  / { sub("^REM  ", ""); }
/^CREATE INDEX/  { spill(); current_file = index_file; }
/^CREATE UNIQUE/ { spill(); current_file = index_file; }
/^ALTER TABLE/   { spill(); current_file = index_file; }
/^CREATE TABLE/  { spill(); current_file = table_file; }

{ append_line(); }

/;$/ { spill(); current_file = trash_file; }

# -----------------------------------------------------------------------------

function append_line()
{
  data=data $0 " ";
}

# -----------------------------------------------------------------------------

function fold_before( t )
{
  i=match(data," " t);
  if (i>0)
  {
    printf("%s\n",substr(data,1,i-1)) >current_file;
    data=substr(data,i+1);
  }
}

# -----------------------------------------------------------------------------

function spill()
{
  gsub("  ", " ",data);  # compress multiple spaces to single space
  sub(" $","",data);     # remove trailing space
  if (""==data) return;
  gsub(" ,", ",",data);  # remove spaces before commas

  fold_before("ADD CONSTRAINT");
  fold_before("FOREIGN KEY");
  fold_before("REFERENCES");
  fold_before("ON");
  fold_before("PRIMARY KEY");
  fold_before("USING INDEX");

  i=match(data,"\" [(]\".*PCTFREE");
  if (i>0)
  {
    printf("%s\n(\n",substr(data,1,i)) >current_file;
    data=substr(data,i+3);
    while (i=match(data,", \""))
    {
      printf("  %s\n",substr(data,1,i)) >current_file;
      data=substr(data,i+2);
    }

    i=match(data,") PCTFREE");
    if (i>0)
    {
      printf("  %s\n",substr(data,1,i-1)) >current_file;
      data=substr(data,i);
    }
  }

  fold_before("PCTFREE");
  fold_before("STORAGE");
  fold_before("TABLESPACE");
  fold_before("DISABLE");

  sub(" ;",";",data);    # remove space before semicolon
  printf("%s\n\n",data) >current_file;
  data="";
}

# -----------------------------------------------------------------------------

END {
  print "SPOOL OFF" >index_file;
  print "SPOOL OFF" >table_file;
  close(index_file);
  close(table_file);
  close(trash_file);
}

# -----------------------------------------------------------------------------

