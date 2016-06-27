#use "base.decls"
#use "util.decls"

typedef INCLUDE_CONF = "#include " FOLDER;;
test INCLUDE_CONF matches "#include myfolder/my_filE.txt";;

typedef INCLUDE_DICT = "{\"@include\"=\""FOLDER"\"}";;
test INCLUDE_DICT matches "{\"@include\"=\"myfolder/my_filE.txt\"}";;

typedef CLEAR_CONF = "#clear" ((" " WORD)*);;
test CLEAR_CONF matches "#clear";;
test CLEAR_CONF matches "#clear mydata:hello tester";;

typedef CLEAR_DICT = "{\"#clear\"" ("{\"name\"=\""WORD"\"}")* "}";;
test CLEAR_DICT matches "{\"#clear\"}";;
test CLEAR_DICT matches "{\"#clear\"{\"name\"=\"mydata:hello\"}{\"name\"=\"tester\"}}";;

typedef ELEMENT_DICT = "{\"@elem\"=\"" QUOTELESS_STRING "\"}";;
test ELEMENT_DICT matches "{\"@elem\"=\"--force-confold\"}";;

typedef KVP_CONF = WORD " \"" DELIMITED_STRING "\"";;
test KVP_CONF matches "hello \"testingh ielloo asdfwer s\"";;
typedef KVP_DICT = "{\""WORD"\"=\""DELIMITED_STRING"\"}";;
test KVP_DICT matches "{\"hello\"=\"testingh ielloo asdfwer s\"}";;

typedef NONRECURSIVE_CONF = (((KVP_CONF | QUOTELESS_STRING) ";") | CLEAR_CONF | MULTILINE_COMMENT | INCLUDE_CONF);;

typedef NONRECURSIVE_DICT = (KVP_DICT | ELEMENT_DICT | CLEAR_DICT | MULTILINE_COMMENT_DICT | INCLUDE_DICT );;

typedef APT_L0_CONF = WORD " {\n" (NONRECURSIVE_CONF "\n")* "}";;
test APT_L0_CONF matches "APT {
hello \"testingh ielloo asdfwer s\";
--force-confold;
/*test
multiline*/
//comment
#clear mydata:hello tester
#include myfolder/my_filE.txt
}";;

typedef APT_L0_DICT = "{\""WORD"\""NONRECURSIVE_DICT*"}";;
test APT_L0_DICT matches "{\"APT\"{\"hello\"=\"testingh ielloo asdfwer s\"}{\"@elem\"=\"--force-confold\"}{\"#mcomment\"{\"string\"=\"test\"}{\"string\"=\"multiline\"}}{\"#comment\"=\"comment\"}{\"#clear\"{\"name\"=\"mydata:hello\"}{\"name\"=\"tester\"}}{\"include\"=\"myfolder/my_filE.txt\"}}";;

apt_l0_dict = [APT_L0_CONF <=> APT_L0_DICT {}]

(*{"APT {
hello \"testingh ielloo asdfwer s\";
--force-confold;
/*test
multiline*/
//comment
#clear mydata:hello tester
#include myfolder/my_filE.txt
}"
<->
"{\"APT\"{\"hello\"=\"testingh ielloo asdfwer s\"}{\"@elem\"=\"--force-confold\"}{\"#mcomment\"{\"string\"=\"test\"}{\"string\"=\"multiline\"}}{\"#comment\"=\"comment\"}{\"#clear\"{\"name\"=\"mydata:hello\"}{\"name\"=\"tester\"}}{\"@include\"=\"myfolder/my_filE.txt\"}}"}]*)
