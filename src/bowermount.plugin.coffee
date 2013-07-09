# Export Plugin
module.exports = (BasePlugin) ->

	path = require('path')
	fs = require('fs')
	bower = require('bower')
	_ = require('underscore')
	levenshtein = require('levenshtein-distance')
	requirejs = require('requirejs/bin/r.js')
	request = require('request')


	# Helper function that retrieves resource by it's path
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
			# By default only enalbed in development environment
			enabled: false
			environments:
				development:
					enabled: true
			# Specify bower component names (like `jquery`, `almond`, etc.)
			# you don't want to be mounted
			excludes: []
			rjsConfig: 'scripts/main.js'

		# Server Extend
		# Used to add our own custom routes to the server before the docpad routes are added
		#
		# Code below mounts bower components in the runtime
		# So, for instance if you have installed `bower install jquery`
		# or `bower install almond` you can access them via web like so:
		# `/scripts/jquery.js` and `/scripts/almond.js` respectively
		# 
		# The code is highly based on grunt-bower-requirejs task:
		# https://github.com/yeoman/grunt-bower-requirejs
		serverExtend: (opts) ->
			# Extract the server from the options
			{server} = opts
			docpad = @docpad
			config = @config

			rjsConfigFilePath = path.join docpad.config.outPath, config.rjsConfig
			if fs.existsSync rjsConfigFilePath
				rjsConfigFile = String( fs.readFileSync String(rjsConfigFilePath) )

			# Redirect Middleware
			server.use (req,res,next) ->
				filePath = path.join docpad.config.outPath, req.url
				fileName = path.basename filePath
				alias = fileName.replace /\.js$/, ""

				fs.exists filePath, (exists) ->
					if exists
						next()

					# Catch URIs like: "/scripts/something.js"
					# but not "/scripts/something"
					# and not "/scripts/subdir/something.js"
					else if /\/scripts\/[^\/]*\.js$/.test filePath
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
												new levenshtein(jsfiles).find alias, (res) ->
													obj[key] = path.join(val, res)
											# Assign the only one that was found
											else if jsfiles.length == 1
												obj[key] = path.join(val, jsfiles[0])

											# Ignore component if no .js file found
											else
												delete obj[key]

								# If alias can be found in bower components - send it's
								# contents
								if _.has components, alias

									if rjsConfigFile
										# Use path set in RequireJS config
										requirejs.tools.useLib (require) ->
											require("transform").modifyConfig rjsConfigFile, (config) ->
												# Overwrite auto-fetched paths with paths specified in RequireJS
												# configuration file
												_.extend(components, config.paths);

												# First cache path in a variable
												componentPath = components[alias]

												if config.paths[alias]
													# Absolute path with extension
													if /^[\/|http]/.test config.paths[alias]
														componentPath = config.paths[alias]
													# Relative path (to baseUrl) without extension
													else
														componentPath = path.join docpad.config.outPath, config.baseUrl, componentPath

												serveComponent componentPath, res, next
									else
										serveComponent components[alias], res, next

								else
									next()

							.on 'error', (err) ->
								next?(err)

					# File neither exists, neither seems to be bower js component
					else
						next()
