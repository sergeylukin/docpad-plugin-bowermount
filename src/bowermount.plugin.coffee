# Export Plugin
module.exports = (BasePlugin) ->

	path = require('path')
	fs = require('fs')
	bower = require('bower')
	_ = require('underscore')

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

									# if there's no main attribute in the bower.json file, for example:
									# "almond": "bower_components/almond/"
									# ..then look for a top level .js file, so we want this:
									# "almond": "bower_components/almond/almond.js"
									# assuming almond.js exists
									# if we don't find one continue to use the original value.
									# if we find any Gruntfiles, remove them
									if not _.isArray(val)
										if fs.statSync(val).isDirectory()
											files = fs.readdirSync val
											main = _.filter files, (fileName) ->
												return path.extname(fileName) is ".js" && fileName != 'Gruntfile.js'
											obj[key] = (if main.length is 1 then path.join(val, main[0]) else val)

								# If alias can be found in bower components - send it's
								# contents
								if _.has components, alias
									componentPath = path.join docpad.config.rootPath, components[alias]
									fs.exists componentPath, (exists) ->
										if exists
											res.writeHead(200, {"Content-Type": "text/plain"});
											res.write fs.readFileSync componentPath
											res.end()
										else
											next()

								else
									next()

							.on 'error', (err) ->
								next?(err)

					# File neither exists, neither seems to be bower js component
					else
						next()