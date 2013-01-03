#!/usr/bin/env python
# -*- coding: utf-8 -*-
 
"""
 TODO: need to find the section number with a query instead of hardcoding it in here.
 TODO: need a way of figuring out the article ID (see mwArticleId below).
"""

import sys, csv, re, string
import urllib, urllib2, json
from hashlib import md5

url = 'https://wiki.domain.tld/w/api.php'
mwUser = 'Treasurer'
mwPassword = '*************'
mwDomain = 'local'
mwPageTitle = 'Finances'
mwArticleId = 0000

"""
 There are two ways to handle anonymization: whitelisting and blacklisting.
 The blacklist takes all contacts that should be anonymized and the whitelist
 takes all contacts that shouldn't be anonymized.
 
 The script looks at both lists for anonymization, i.e. you can use either or both.
"""

blacklist = ['Membership fee', '[Split Transaction]', 'Events: Haxogreen: Registration']
whitelist = [
	'Open source certification',
	'OLIFANTASIA',
	'Ultimaker',
	]

def main():
	data = '==Detail==\n\n' + parse()
	if transmit(data):
		print 'Success!'

def apiRequest(params, headers={}):
	""" Do an actually web request and return the json response """
	req = urllib2.Request(url, params, headers)
	response = urllib2.urlopen(req).read()
	return json.loads(response)

def transmit(data):
	""" Prepare the web request according to the mediawiki API """
	# md5 the data to prevent corruption
	texthash = md5(data).hexdigest()

	print "Logging into wiki..."
	# Request a login token
	params = urllib.urlencode({
	'action' : 'login',
	'lgname' : mwUser,
	'lgpassword' : mwPassword,
	'lgdomain' : mwDomain,
	'format' : 'json'
	})
	respobj = apiRequest(params)

	if respobj['login']['result'] == 'NeedToken':
		# Confirm login request
		params = urllib.urlencode({
			'action' : 'login',
			'lgname' : mwUser, 
			'lgpassword' : mwPassword,
			'lgdomain' : mwDomain,
			'lgtoken' : respobj['login']['token'],
			'format' : 'json'
		})
		prefix = respobj['login']['cookieprefix']
		headers = { 'Cookie' : prefix + '_session=' +  respobj['login']['sessionid'] }
		respobj = apiRequest(params, headers)

	if respobj['login']['result'] == 'Success':
		print 'Login successful, requesting edit token...'
		# set cookie
		headers = {
			'Cookie' : prefix + 'UserID=' + str(respobj['login']['lguserid']) + ';'
			+ prefix + '_session=' + respobj['login']['sessionid'] + ';'
			+ prefix + 'UserName=' + mwUser + ';' + prefix + 'Token=' + respobj['login']['lgtoken']
		}
		# Now get an edit token
		params = urllib.urlencode({
			'action' : 'query',
			'prop' : 'info|revisions',
			'intoken' : 'edit',
			'titles' : mwPageTitle,
			'format' : 'json'
		})
		editobj = apiRequest(params, headers)
		if editobj:
			print 'Editing page...'
			# No idea how to actually get the pageid from the dict
			params = urllib.urlencode({
				'action' : 'edit',
				'title' : mwPageTitle,
				'section' : 3,	# This is the "detail section" TODO!!
				'text' : data,
				'md5' : texthash,
				'summary' : 'Automated finances commit',
				'bot' : True,
				'nocreate' : True,
				'basetimestamp' : editobj['query']['pages'][mwArticleId]['revisions'][0]['timestamp'],
				'format' : 'json',
				'token' : editobj['query']['pages'][mwArticleId]['edittoken']
			})
			result = apiRequest(params,headers)
			if result['edit']['result'] == 'Success':
				return 1
	else:
		print 'Error', respobj['login']['result']

		
def expensify(amount):
	""" Turn expenses into a red string """
	val = stringToFloat(amount)
	if val < 0:
		return 'style="color:red;" | ' + str(val)
	else:
		return str(val)


def stringToFloat(amount):
	""" Cast and transform strings into floats """
	amount = str(amount)	# necessary for regex
	expense = re.match(r'\((\d+\.\d{2})\)', amount)
	if expense != None:
		amount = '-' + expense.group(1)
	else:
		amount =  amount.strip()
	return float(amount)


def parse():
	""" Parse the csv export and return mediawiki syntax """
	string = table = ''
	topen = transactions = somme = 0
	handle = open(sys.argv[1],'r')
	rows = csv.reader(handle, delimiter=',', quotechar='"')
	for row in rows:
		if len(row) <  2:
			match = re.search(r'^Month of (\d+)-(\d+)-\d+$', row[0])
			if match != None:
				string += '=== ' + match.group(1) + '-' + match.group(2) + '===\n'
				string += '{| class="wikitable sortable" style="width:80%"\n'
				string += "|+ Transactions for month %s-%s" % (match.group(1),match.group(2))
				string += '\n|-\n'
				string += '! Date !! Payee !! Category !! Amount'
				topen = 1
		elif len(row) == 2:
			match = re.search(r'^Total Month of (\d+)-(\d+)-\d+$', row[0])
			if match != None:
				# forget row[1]
				total = expensify( somme )
				string += '|-\n'
				string += '! colspan="3" | Total || ' + total + '\n'
				string += '|}\n\n'
				somme = 0	# reset amount after totalling
		elif len(row) > 4 and row[0] != 'Date':
			# This is a transaction, let's count them!
			transactions += 1
			# anonymize payments
			if row[1] not in public or row[2] in anonymize:
				row[1] = 'Anonymized'

			transfer = re.search(r'^Transfer', row[2])
			if transfer != None:
				#transfers += stringToFloat(row[3].strip())
				# Not used right now
				continue
			else:
				somme += stringToFloat(row[3].strip())

			row[3] = expensify(row[3].strip())

			if topen:
				string += '|-\n'

			string += '| ' + row[0] + ' || ' + row[1] + ' || ' + row[2] + ' || ' + row[3]

		if string:
			table += string + '\n'
			string = ''
	print "%d transactions parsed." % transactions
	return table

if __name__ == "__main__" :
	if len(sys.argv) < 2:
		print 'Usage: ' + sys.argv[0] + ' transactions_file.csv'
		exit(0)
	main()
