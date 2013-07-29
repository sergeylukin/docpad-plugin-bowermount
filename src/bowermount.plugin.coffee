# Export Plugin
module.exports = (BasePlugin) ->

	path = require('path')
	fs = require('fs')
	_ = require('underscore')
	# bower provides us with the list of installed components
	bower = require('bower')
	# requirejs let's us fetch and modify RequireJS configuration
	requirejs = require('requirejs/bin/r.js')
	# Used to find best match in component main JS filename auto-detection
	levenshtein = require('levenshtein-distance')
	# Used to resolve URIs
	request = require('request')

	# Retrieves resource by it's path
	# path's value may be in following formats:
	#
	#   http://uri.to/the/file
	#   http://uri.to/the/file.js
	#
	#   /full/path/to/file
	#   /full/path/to/file.js
	#
	serveComponent = ( componentPath, res, next ) ->
		# append extension
		unless /\.js$/.test componentPath
			componentPath += '.js'

		# Fetch URL from the network
		if /^http/.test componentPath
			# console.log 'bowermount: fetching ' + componentPath
			request componentPath, (err, response, body) ->
				if !err and response.statusCode == 200
					res.writeHead(200, {"Content-Type": "text/javascript"});
					res.write body
					res.end()
				else
					next()

		# Serve file from FileSystem
		else
			# docpad.log 'info', 'bowermount: loading ' + componentPath
			fs.exists componentPath, (exists) ->
				if exists
					res.writeHead(200, {"Content-Type": "text/javascript"});
					res.write fs.readFileSync componentPath
					res.end()
				else
					next()

	# Define Plugin
	class BowerMountPlugin extends BasePlugin
		# Plugin name
		name: 'bowermount'

		# Plugin configuration
		config:
			# Disable this plugin by default
			enabled: false
			# Only enable for development environment
			environments:
				development:
					enabled: true
			# list of bower components or RequireJS paths aliases
			# (like `jquery`, `almond`, etc.)
			# that shouldn't be mounted
			excludes: []
			# relative path to JS file with RequireJS paths configuration
			# it's relative to current environment's "outPath"
			# so, for example, if running in development environment and 
			# "outPath" is set to "./out" and JS file with RequireJS configuration
			# is compiled into "./out/scripts/main.js" then the correct path would be
			# "scripts/main.js"
			rjsConfig: 'scripts/main.js'
			# Change filename for paths map created and used by this plugin
			mountMapPath: '.tmp.bowermount.json'

		# When app is generated - go over all Bower components and RequireJS paths
		# and create "Paths Map" file which is used to map future requests to
		# unexisting files
		generateAfter: ({server}) ->
			# Prepare
			docpad = @docpad
			config = @config
			# Fetch contents of RequireJS configuration file
			rjsConfigFilePath = path.join docpad.config.outPath, config.rjsConfig
			if fs.existsSync rjsConfigFilePath
				rjsConfigFile = fs.readFileSync String(rjsConfigFilePath), 'utf8'

			# Path to file that keeps "Paths Map"
			mountMapPath = path.join docpad.config.outPath, config.mountMapPath

			bower.commands.list({paths: true})
				.on 'data', (components) ->

					# Iterate through Bower components
					_.each components, (componentPath, componentName, obj) ->

						# Ignore this component
						if config.excludes.indexOf(componentName) isnt -1
							delete obj[componentName]
							return

						# Don't bother with arrays, just take the first one
						# ..if it's not the one we need, it can be specified
						# in RequireJS configuration
						componentPath = obj[componentName] = obj[componentName][0] if _.isArray(componentPath)

						# If path set in bower leads to a directory
						# auto-detect the filename inside it
						if fs.statSync(componentPath).isDirectory()
							# First, fetch only JS files
							jsfiles = _.filter fs.readdirSync(componentPath), (fileName) ->
								return path.extname(fileName) is ".js" && fileName != 'Gruntfile.js'

							# If there are more than 1 candidate - find best
							# match using levenshtein distance
							if jsfiles.length > 1
								new levenshtein(jsfiles).find componentName, (res) ->
									obj[componentName] = path.join(componentPath, res)
							# If only one was found - most like that is the file we need
							else if jsfiles.length == 1
								obj[componentName] = path.join(componentPath, jsfiles[0])

							# Ignore component if no .js file found
							else
								delete obj[componentName]

					# Enter RequireJS configuration
					if rjsConfigFile
						requirejs.tools.useLib (require) ->
							rjsConfig = require("transform").modifyConfig rjsConfigFile, (rconfig) ->
								# Normalize paths set in requirejs
								# So for example, ../../bower_components/... will be converted
								# to full path
								_.each rconfig.paths, (rjsModulePath, rjsModuleName, obj) ->
									if config.excludes.indexOf(rjsModuleName) is -1
										obj[rjsModuleName] = path.join docpad.config.outPath, rconfig.baseUrl, rjsModulePath
								# Merge paths found in Bower with paths found in RequireJS
								# into one JSON string and write to "Paths Map" file
								mergedPaths = _.extend components, rconfig.paths
								fs.writeFileSync mountMapPath, JSON.stringify(mergedPaths)

								# Overwrite RequireJS configuration file so that
								# it's paths will point to same pattern URI: /scripts/LIB_NAME
								# for example jquery would point to /scripts/jquery.js
								# underscore would point to /scripts/underscore.js etc.
								_.each components, (rjsModulePath, rjsModuleName, obj) ->
									# only if this component is not in "excludes" array
									if config.excludes.indexOf(rjsModuleName) is -1
										rconfig.paths[rjsModuleName] = rjsModuleName
								_.each rconfig.paths, (rjsModulePath, rjsModuleName, obj) ->
									# only if this component is not in "excludes" array
									if config.excludes.indexOf(rjsModuleName) is -1
										rconfig.paths[rjsModuleName] = rjsModuleName
								# Return pathed RequireJS configuration file
								rconfig

							# Write new RequireJS configuration it's file
							fs.writeFile rjsConfigFilePath, rjsConfig, (err) ->
								docpad.log 'info', "Patched RequireJS paths to point to bowermount"
					else
						fs.writeFileSync mountMapPath, JSON.stringify(components)

				.on 'error', (err) ->
					console.log 'Oops could not fetch bower components'

		# Server Extend
		# Used to add our own custom routes to the server before the docpad routes are added
		#
		# Code below extends server so that it can serve resources that are specified in
		# "Paths Map" file if they don't exist
		serverExtend: (opts) ->
			# Prepare
			{server} = opts
			docpad = @docpad
			config = @config

			rjsConfigFilePath = path.join docpad.config.outPath, config.rjsConfig
			# Path to file that keeps "Paths Map"
			mountMapPath = path.join docpad.config.outPath, config.mountMapPath

			# Start server middleware
			server.use (req,res,next) ->
				# Full path of requested file, like:
				# "/var/www/app/out/scripts/zepto.js"
				filePath = path.join docpad.config.outPath, req.url
				# Just filename, like:
				# "zepto.js"
				fileName = path.basename filePath
				# Alias - filename without extension
				# alias is used when looking for path in "Paths Map" file
				alias = fileName.replace /\.[^/.]+$/, ""

				# If file doesn't exist but it matches our scripts pattern and is
				# found in "Paths Map" file - then serve it's path
				#
				# Scripts pattern is: "/scripts/something.js"
				# but not "/scripts/something"
				# and not "/scripts/subdir/something.js"
				if /\/scripts\/[^\/]*\.js$/.test req.url
					fs.exists filePath, (exists) ->
						if exists
							serveComponent filePath, res, next
						# Read "Paths Map" file
						else if fs.existsSync mountMapPath
							pathsMap = JSON.parse fs.readFileSync(mountMapPath)
							# If file's path exists in paths map
							if pathsMap[alias]
								# Serve absolute and http paths 'as is'
								if /^[\/|http]/.test pathsMap[alias]
									componentPath = pathsMap[alias]
								# Normalize relative paths
								else
									componentPath = path.join docpad.config.rootPath, pathsMap[alias]

								serveComponent componentPath, res, next
							else
								next()
						else
							next()

				else
					next()
