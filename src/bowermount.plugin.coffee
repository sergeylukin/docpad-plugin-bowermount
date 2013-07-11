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
			console.log 'bowermount: fetching ' + componentPath
			request componentPath, (err, response, body) ->
				if !err and response.statusCode == 200
					res.writeHead(200, {"Content-Type": "text/javascript"});
					res.write body
					res.end()
				else
					next()

		# Serve file from FileSystem
		else
			console.log 'bowermount: loading ' + componentPath
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
			# list of bower components (like `jquery`, `almond`, etc.)
			# that shouldn't be mounted
			excludes: []
			# relative path to JS file with RequireJS paths configuration
			# it's relative to "outPath" set in current environment
			# so, for example, if running in development environment and 
			# "outPath" is set to "./out" and JS file with RequireJS configuration
			# is compiled into "./out/scripts/main.js" then the correct path would be
			# "scripts/main.js"
			rjsConfig: 'scripts/main.js'

		# Server Extend
		# Used to add our own custom routes to the server before the docpad routes are added
		#
		# Code below mounts bower components in the runtime
		# So, for instance if your server is accessible via
		# `http://localhost:9778/` and you have installed jquery:
		# `bower install jquery`
		# or almond:
		# `bower install almond` then you would be able to access
		# them via web via:
		# `http://localhost:9778/scripts/jquery.js`
		# and
		# `http://localhost:9778/scripts/almond.js`
		# 
		# The code is highly based on `grunt-bower-requirejs` task:
		# https://github.com/yeoman/grunt-bower-requirejs
		serverExtend: (opts) ->
			# Prepare
			{server} = opts
			docpad = @docpad
			config = @config
			rjsConfigFilePath = path.join docpad.config.outPath, config.rjsConfig
			rjsCached = 0

			# Start server middleware
			server.use (req,res,next) ->
				# Full path of file requested, like:
				# "/var/www/app/out/scripts/zepto.js"
				filePath = path.join docpad.config.outPath, req.url
				# Just filename, like:
				# "zepto.js"
				fileName = path.basename filePath
				# Alias - filename without extension
				# alias is used to match requested file with
				# bower component and with name of requirejs path
				alias = fileName.replace /\.[^/.]+$/, ""

				# Fetch contents of RequireJS configuration file
				# Note: it's optional, if file is not found, we'll use
				# auto-detection mechanism to resolve paths to bower components
				# however if RequireJS configuration file exists
				# then we will rely on what is specified in it's `paths` directive
				if fs.existsSync rjsConfigFilePath
					rjsConfigFile = fs.readFileSync String(rjsConfigFilePath), 'utf8'
					rjsCachePath = path.normalize docpad.config.outPath + '/.rjs.cache'

				# First of all, we want to know if requested file exists or not
				# If it exists and it's not the file that contains RequireJS
				# configuration - then just serve it "as is", however if it's the file
				# with RequireJS configuration then we want to manipulate it:
				#   - save it's `paths` directive somewhere for internal use. We'll
				#   need it as a map to sources when serving mounted files
				#   - set mounts relative paths instead of source paths. So if config
				#   looks like so:
				#     baseUrl: 'scripts/',
				#     paths: {
				#       'jquery': 'http://url/to/jquery',
				#       'underscore': '/somewhere/in/my/system/underscore.js'
				#     }
				#   then change it to:
				#     baseUrl: 'scripts/',
				#     paths: {
				#       'jquery': 'jquery',
				#       'underscore': 'underscore'
				#     }
				#
				#   assuming both jquery and underscore exist in the list of bower
				#   installed components
				#
				#   so that jquery and underscore will be downloaded from
				#   "scripts/jquery.js" and "scripts/underscore.js"
				#
				# Now if requested file doesn't exist - it's most likely the file we
				# want to mount to it's source, would it be source we know from
				# RequireJS configuration we saved earlier or auto-detection
				#
				fs.exists filePath, (exists) ->
					# If any static existing file requested
					if exists
						# If any file that is not RequireJS config file
						if filePath != rjsConfigFilePath
							next()
						# If RequireJS config file requsted
						else
							# go over all bower components and remove their paths in RequireJS
							# remember paths in object which will be then used in resolving
							bower.commands.list({paths: true})
								.on 'data', (components) ->

									# remove excludes and clean up key names
									_.each components, (val, key, obj) ->
										if config.excludes.indexOf(key) isnt -1
											delete obj[key]
											return

										# clean up path names like 'typeahead.js'
										# when requirejs sees the .js extension it will assume
										# an absolute path, which we don't want.
										if path.extname(key) is ".js"
											newKey = key.replace(/\.js$/, "")
											obj[newKey] = obj[key]
											delete obj[key]

											console.log "Warning: Renaming " + key + " to " + newKey

										if not _.isArray(val)
											# If path set in bower leads to a directory
											# try to find file in it by ourselves..
											if fs.statSync(val).isDirectory()
												jsfiles = _.filter fs.readdirSync(val), (fileName) ->
													return path.extname(fileName) is ".js" && fileName != 'Gruntfile.js'

												# Find best match using levenshtein distance
												# algorithm if there are many .js files
												if jsfiles.length > 1
													new levenshtein(jsfiles).find alias, (res) ->
														obj[key] = path.join(val, res)
												# Assign the only one that was found
												else if jsfiles.length == 1
													obj[key] = path.join(val, jsfiles[0])

												# Ignore component if no .js file found
												else
													delete obj[key]

									# Write paths to RequireJS
									if rjsConfigFile
										# Use path set in RequireJS config
										requirejs.tools.useLib (require) ->
											rjsConfig = require("transform").modifyConfig rjsConfigFile, (config) ->
												# Save RequireJS paths in file
												if rjsCached is 0
													fs.writeFileSync rjsCachePath, JSON.stringify(config.paths)
													rjsCached = 1
												# Change RequireJS paths for Bower components
												# so that jquery would be jquery
												# underscore would be underscore etc.
												_.each components, (val, key, obj) ->
													config.paths[key] = key
												config

											# Update file with RequireJS configuration
											fs.writeFile filePath, rjsConfig, (err) ->
												console.log "Updated RequireJS config"
												# Serve RequireJS file from FileSystem
												res.writeHead(200, {"Content-Type": "text/javascript"});
												res.write fs.readFileSync filePath
												res.end()
									else
										next()

								.on 'error', (err) ->
									next?(err)


					# If a script requested - check whether special route is
					# assigned to it and mount it if needed
					# Catch URIs like: "/scripts/something.js"
					# but not "/scripts/something"
					# and not "/scripts/subdir/something.js"
					else if /\/scripts\/[^\/]*\.js$/.test req.url
						# Fetch all installed bower components
						bower.commands.list({paths: true})
							.on 'data', (components) ->

								# remove excludes and clean up key names
								_.each components, (val, key, obj) ->
									if config.excludes.indexOf(key) isnt -1
										delete obj[key]
										return

									# clean up path names like 'typeahead.js'
									# when requirejs sees the .js extension it will assume
									# an absolute path, which we don't want.
									if path.extname(key) is ".js"
										newKey = key.replace(/\.js$/, "")
										obj[newKey] = obj[key]
										delete obj[key]

										console.log "Warning: Renaming " + key + " to " + newKey

									if not _.isArray(val)
										# If path set in bower leads to a directory
										# try to find file in it by ourselves..
										if fs.statSync(val).isDirectory()
											jsfiles = _.filter fs.readdirSync(val), (fileName) ->
												return path.extname(fileName) is ".js" && fileName != 'Gruntfile.js'

											# Find best match using levenshtein distance
											# algorithm if there are many .js files
											if jsfiles.length > 1
												new levenshtein(jsfiles).find alias, (result) ->
													obj[key] = path.join(val, result)
											# Assign the only one that was found
											else if jsfiles.length == 1
												obj[key] = path.join(val, jsfiles[0])

											# Ignore component if no .js file found
											else
												delete obj[key]

								# If alias can be found in bower components - send it's
								# contents
								if _.has components, alias

									componentPath = components[alias]

									if rjsConfigFile
										# Use path set in RequireJS config
										requirejs.tools.useLib (require) ->
											require("transform").modifyConfig rjsConfigFile, (rjsConfig) ->

												# Read from cache file
												if fs.existsSync rjsCachePath
													pathsCache = JSON.parse fs.readFileSync(rjsCachePath)
													if pathsCache[alias]
														# Absolute path with extension
														if /^[\/|http]/.test pathsCache[alias]
															componentPath = pathsCache[alias]
														# Relative path (to baseUrl) without extension
														else
															componentPath = path.join docpad.config.outPath, rjsConfig.baseUrl, pathsCache[alias]

												serveComponent componentPath, res, next
									else
										serveComponent componentPath, res, next

								else
									next()

							.on 'error', (err) ->
								next?(err)

					# File neither exists, neither seems to be bower js component
					else
						next()
