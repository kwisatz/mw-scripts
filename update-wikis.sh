#!/bin/bash
# Wiki maintenance script by David Raison <david@raison.lu>
# (Inspired by work from Jeroen de Dauw <jeroendedauw@gmail.com>)
# Licensed under a GPLv3 license
# 
# v 0.03

## Todo
## * check permissions before attempting to create directories
## * implement tags
## * implement restoring wikis/snapshots
## * when choosing only to update extensions, there is no need to ask for a wiki
## * local/custom repositories need additional information, cf. openduino/mwextension => OpenDuino

# set -x

# kick out mr root
if [ $(id -un) = "root" ]
then
  echo "Please don't run as root"
  exit 1
fi

## Vars
WEBHOME="/var/www"
EXTENSIONS="/var/local/mediawiki/extensions"

# only used at installation time
WIKISOURCE="http://svn.wikimedia.org/svnroot/mediawiki/branches/REL1_16/phase3"

PUBLIC="http://svn.wikimedia.org/svnroot/mediawiki/trunk/extensions"
PUBLICTAGS="http://svn.wikimedia.org/svnroot/mediawiki/tags/extensions"
PRIVATE="svn+ssh://svn.wikimedia.org/svnroot/mediawiki/trunk/extensions"
LOCAL="file:///var/repo/projects"

BACKUPDIR="/var/backups/mw-backups"

wikis=( hackerspace.lu/www/w haxogreen.lu/www/w hacker.lu/dev/w )

e_public=( Validator Maps SemanticMediaWiki SemanticDrilldown SemanticMaps SemanticForms SemanticResultFormats Awesomeness SemanticCompoundQueries ParserFunctions StringFunctions ConfirmEdit UserMerge ExternalData FlashMP3 Flattr SyntaxHighlight_GeSHi OggHandler SemanticFormsInputs WikiCategoryTagCloud FCKeditor LdapAuthentication Renameuser Drafts Lockdown LiquidThreads)
e_private=( QrCode AmazonPartnerLink DateDiff SlimboxThumbs )
e_local=( openduino )

# update scripts
# mediawiki
# i.e. wikihome/maintenance/update.php
# semantic mediawiki has it's own
# /var/local/mediawiki/extensions/SemanticMediaWiki/maintenance/SMW_setup.php
extension_setups=( SemanticMediaWiki/maintenance/SMW_setup.php )


#################################################################################
## THIS is as far as it goes. As a user, don't touch anything below this line. ##
#################################################################################

REVERTFILE=`pwd`'/.revert-'`date +'%s'`
trees=( trunk tags )
#changes=( all core extensions switchtree revert )
changes=( all core extensions switchtree )

echo "Doing preliminary checks..."

#[ -x "`which git`" ] || ( echo "git not available, bailing out." && exit 1; )
[ -x "`which svn`" ] || ( echo "svn not available, bailing out." && exit 1; )
#[ -x "/var/backups/mysql/backup_db.sh" ] || ( echo "mysql backup script not found, aborting." && exit 1; )

echo "... everything seems to be ok!"


## Functions
check_return(){
  ret=$?
  if [ $ret -ne 0 ]
  then
    echo "ERROR: something did not work, we got exit code $ret"
    echo "see above if you see some error cause"
    echo "You may want to restore from the backups if stuff is broken"
    echo "Do you want to continue anyway? [y/N]"
    read ans
    if [ "$ans" = "y" ] || [ "$ans" = "Y" ]
    then
      return $ret
    fi
    exit $ret
  fi
}

in_array(){
    local i
    needle=$1
    shift 1
    # array() undefined
    [ -z "$1" ] && return 1
    for i in $*
    do
	    [ "$i" == "$needle" ] && return 0
    done
    return 1
}

## select between trunk and tags,
## if tags chosen, 
## * get list of recent tags
## * get current tag
get_tree(){
declare -a e_fromsvn
for ext in ${e_public[@]}; do
	if [ -d ${EXTENSIONS}/${ext}/.svn ]; then
		e_fromsvn=( ${e_fromsvn[@]} $ext );
	fi
done
echo "Which extension would you like to switch?"
select extension in ${e_fromsvn[@]}; do
	if in_array $extension ${e_fromsvn[@]}; then
		get_tree_for_extension $extension;
		populate_tree_list $extension;
		break
	fi
done
}

## We could merge the following two functions

get_tree_for_extension(){
echo -n "$1 is currently on tree "
svn info ${EXTENSIONS}/$1 | grep URL | grep trunk > /dev/null
if [ $? -eq 0 ]; then
	echo "trunk"
else 
	echo -n "tags"
	# find what REL
	rel=`svn info ${EXTENSIONS}/$1 | grep URL`
	echo " (${rel##*/})"
fi
}

get_current_revision(){
revision=`svn info ${EXTENSIONS}/${1} | grep Revision | awk '{print $2}'`
echo "${i}:$revision" >> $REVERTFILE
}

populate_tree_list() {
echo "Fetching list of available releases..."
declare -a e_list
e_list=( ${e_list[@]} 'trunk' );
url=`svn info ${EXTENSIONS}/$1 | grep URL | awk '{print $2}'` 
## adapt to current tree (unelegant :( )
choice=`echo $url | grep trunk > /dev/null`
if [ $? -eq 0 ]; then
	current="trunk"
	url=${url/trunk/tags}
else
	current="tags"
	url=${url%/*}
fi
for rel in `svn list ${url}`; do
	e_list=( ${e_list[@]} $rel );
done
select rel in ${e_list[@]}; do
	if in_array $rel in ${e_list[@]}; then
		do_switch_extension $extension $url $current $rel
		break
	fi
done
}

# $1=extension $2=url $3=current $4=chosen
do_switch_extension() {
cd ${EXTENSIONS}/$1
check_return
if [ "$3" == "$4" ]; then
	echo "No change requested."
elif [ "$4" == "trunk" ]; then
	svn switch ${url/tags/trunk}
        check_return
else
	svn switch $2/$4
        check_return
fi
}


get_changes(){
echo ""
echo "What would you like to do?"
select change in ${changes[@]}; do
	if in_array $change ${changes[@]}; then	
	    break
	fi
done
}

get_wiki(){
echo "Choose the wiki:"
select wiki in ${wikis[@]}; do
if in_array $wiki ${wikis[@]}; then
    break
fi
done
}

dump_database(){
backup="${BACKUPDIR}/${1%/*/*}/db.sql-`date +'%s'`.xz"
echo -n "  Dumping database to $backup..."
## First we need to get the appropriate credentials
FILE="${WEBHOME}/${1}/LocalSettings.php"
t1=`awk '($1=="$wgDBname") { print $3 }' < $FILE`; p1=${t1%[\'\"]*}; DB=${p1#[\'\"]*};
t2=`awk '($1=="$wgDBserver") { print $3 }' < $FILE`; p2=${t2%[\'\"]*}; HOST=${p2#[\'\"]*};
t3=`awk '($1=="$wgDBuser") { print $3 }' < $FILE`; p3=${t3%[\'\"]*}; USER=${p3#[\'\"]*};
t4=`awk '($1=="$wgDBpassword") { print $3 }' < $FILE`; p4=${t4%[\"\']*}; PASS=${p4#[\'\"]*};

## Creating mysqldump
`which mysqldump` -u ${USER} -p${PASS} -h${HOST} ${DB} | `which xz` -q > ${backup}
check_return
echo "done."
}

while true; do

get_changes

if [ "$change" == "switchtree" ]; then
	get_tree
fi

if [ "$change" == "revert" ]; then
	get_revision_history
fi


if [ "$change" == "extensions" ] || [ "$change" == "all" ]; then
	echo "Initiating wiki updates..."
	echo "Initiating extension retrieval..."

	## Adding failed extensions to a list
	declare -a e_failed 
	
	## public extensions
	for i in ${e_public[@]}; do
		if [ -d ${EXTENSIONS}/${i} ]; then	
			echo "Storing current revision of ${i}."
				get_current_revision $i 
				echo -n "Updating ${i}: "
	 			svn up ${EXTENSIONS}/${i}
				check_return
			else 
				svn co ${PUBLIC}/${i} ${EXTENSIONS}/${i}
				check_return
			fi
		
			if [ $? -ne 0 ]; then
				echo "Failed updating extension ${i}";
				e_failed=( ${e_failed[@]} $i );
			else
				# run setup
				for setup in ${extension_setups[@]}
				do
				  if [ "${setup#${i}/}" != "${setup}" ]
				  then
				    oldPWD=$PWD
				    echo "running $setup";
				    cd "${EXTENSIONS}$(dirname $setup)"
				    check_return
				    php ./$(basename $setup)
				    check_return
				    cd "$PWD"
				    check_return
				  fi
				done
			fi
		done
		
		# private extensions
		for i in ${e_private[@]}; do
			echo -n "Updating ${i}: "
			if [ -d ${EXTENSIONS}/${i} ]; then	
				svn up ${EXTENSIONS}/${i}
				check_return
			else 
				svn co ${PRIVATE}/${i} ${EXTENSIONS}/${i}
				check_return
			fi
		
			if [ $? -ne 0 ]; then
				echo "Failed updating extension ${i}";
				e_failed=( ${e_failed[@]} $i );
			fi
		done
		
		# local extensions
		for i in ${e_local[@]}; do
			echo -n "Updating ${i}: "
			if [ -d ${EXTENSIONS}/${i} ]; then	
				svn up ${EXTENSIONS}/${i}
				check_return
			else 
				svn co ${LOCAL}/${i} ${EXTENSIONS}/${i}
				check_return
			fi
		
			if [ $? -ne 0 ]; then
				echo "Failed updating extension ${i}";
				e_failed=( ${e_failed[@]} $i );
			fi
		done
		
		if [ ${#e_failed[@]} -gt 0 ]; then
			echo "Failed to fetch or update these extensions: ${e_failed[@]}"
		fi

	fi

	if [ "$change" == "core" ] || [ "$change" == "all" ]; then

		get_wiki

		# Normalize wiki list
		if [ $wiki != "all" ]; then
		    update=( $wiki )
		fi

		# Apply the changes for all spaces
		for wiki in ${update[@]}; do
			echo "Starting update of wiki $wiki..."
			
			wikifolder="${WEBHOME}/${wiki}"
			thisbackup="${BACKUPDIR}/${wiki%/*/*}"
			oldball="${thisbackup}/mw-`date +'%s'`.txz"
		
			[ -d ${thisbackup} ] || mkdir -p ${thisbackup}
			dump_database $wiki
		
			if [ -d "$wikifolder" ]; then
			echo "  Creating backup of $wikifolder in $oldball."
			echo -n "  This may take a while..."
				`which tar` pcf $oldball --lzma --exclude=images $wikifolder 2> /dev/null
				if [ $? -eq 0 ]; then
					echo "done."
					echo "  Updating MediaWiki core..."
					svn up $wikifolder
					check_return
					echo "  Existing installation, running update script..."
					`which php` ${wikifolder}/maintenance/update.php
					check_return
				else
					echo "  failed!"
					exit 1
				fi
			else
				## check if the parent folder even exists (check whether it is writeable, if not, tell the user!!)
				[ -d ${wikifolder%/*/} ] || mkdir -p ${wikifolder%/*/}
				svn co $WIKISOURCE $wikifolder
				check_return
			fi
			echo "  Linking extensions folder..."
			rm -rf ${wikifolder}/extensions && ln -s ${EXTENSIONS} ${wikifolder}/extensions
			check_return

		    echo "... wiki $wiki updated."
		done
		echo "... all wikis have been updated."
		
	fi
done

exit 0;
