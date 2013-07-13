## History

v2.0.0 July 7, 2013
- Initial working version

v2.0.1 July 7, 2013
- Add more details in README

v2.0.2 July 8, 2013
- Add undescore and bower to the list of dependencies

v2.1.0 July 8, 2013
- Improve the way component main file is picked (using levenshtein distance
  algorithm)

v2.1.1 July 8, 2013
- Change serving files "Content-type" to text/javascript

v2.1.2 July 8, 2013
- Fix components serving that have only one single JS file in their root directory

v2.2.0 July 9, 2013
- Rely on RequireJS paths configuration first, fallback to auto-decision
- Support relative, absolute, url paths

v2.2.1 July 10, 2013
- Fix path extension bug. Now paths are extension-agnostic

v2.2.2 July 10, 2013
- Restore Content-type back to text/javascript

v2.2.3 July 11, 2013
- Setup proxy that mounts resources and redirect RequireJS paths to it

v2.2.4 July 11, 2013
- Fix Windows compatibility by using safer methods when manipulating paths

v2.2.5 July 14, 2013
- Fix reading bower components with more than 1 main file
