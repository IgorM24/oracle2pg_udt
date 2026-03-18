/************************************************************************
 * init.sql - initialization for sqlplus script parameters              *
 *                                                                      *
 * @project    Oracle2PG Migration Toolkit                              *
 * @file       init.sql                                                 *
 * @author     Igor Melnikov                                            *
 * @version    1.0.0                                                    *
 * @history                                                             *
 *  Igor Melnikov 18.11.2025 - created                                  *
 ************************************************************************
 * Copyright: FelixDB Software                                          *
 * email: melnikov_ii@mail.ru                                           *
 ***********************************************************************/

set feedback off

define 1=" "
define 2=" "
define 3=" "
define 4=" "
define 5=" "
define 6=" "
define 7=" "
define 8=" "
define 9=" "
define 10=" "
define 11=" "
define 12=" "
define 13=" "
define 14=" "
define 15=" "
define 16=" "
define 17=" "
define 18=" "
define 19=" "
define 20=" "


set echo off 
define NOW_STR= 

column NOW_STR new_value NOW_STR

select
  to_char(sysdate,'dd.mm.yyyy hh24:mi:ss') as NOW_STR
from
  dual;


prompt Oracle2PG Migration Toolkit: Release 1.0.0.0.0 - Production on &NOW_STR
prompt 
prompt Copyright (c) 2025, Igor Melnikov.  All rights reserved.                                                                
prompt
prompt Successfully initialized!

prompt 

