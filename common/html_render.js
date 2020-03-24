var page = require('webpage').create();
var fs = require('fs');
var system = require('system');

String.prototype.endsWith = function(suffix) {
	return this.indexOf(suffix, this.length - suffix.length) !== -1;
};
String.prototype.contains = function(seg) {
	return this.indexOf(seg) !== -1;
};
var getLocation = function(href) {
	    var l = document.createElement("a");
		l.href = href;
		return l;
};

var log = function(string) {
	var time = new Date();
	var timestamp = time.toLocaleTimeString().split(' ')[0] + '.' + time.getMilliseconds();
	timestamp = (timestamp + '        ').slice(0,15);
	console.log(timestamp + '  ' + string);
}

var compareUrl = function(url1, url2) {
	var location1 = getLocation(url1);
	var location2 = getLocation(url2);
	var ret = (location1.hostname == location2.hostname) && (location1.pathname == location2.pathname);
	if (ret == true) return true;
	// When target page load finished, path might be different from 
	// the one from pageLoadFinished(url)
	// Case A: path would be a little different with suffix.
	// 	Example: /p/5301633  - /p/5301633.html
	// Case B: path could just be a slash /
	// 	Example: /  - /p/5301633.html
	// 	https://www.huxiu.com/article/290768.html?f=wangzhan
	log("url not equal:\n" + url1 +
			"\nHOST: " + location1.hostname + 
			"\nPATH: " + location1.pathname +
			"\n" + url2 +
			"\nHOST: " + location2.hostname + 
			"\nPATH: " + location2.pathname
	   );
	if (location1.hostname == location2.hostname) {
		var diffSuffix = null;
		if (location1.pathname.indexOf(location2.pathname) == 0) {
			diffSuffix = location1.pathname.substring(location2.pathname.length);
		} else if (location2.pathname.indexOf(location1.pathname) == 0) {
			diffSuffix = location2.pathname.substring(location1.pathname.length);
		}
		if (diffSuffix == null) return false;
		log("pathname difference: " + diffSuffix);
		var expectedHtmlSuffix = new RegExp(/^\.[a-zA-Z]{1,4}$/);
		if (expectedHtmlSuffix.test(diffSuffix)) {
			log("difference looks like a expected html suffix, treat two URLs as same.");
			return true;
		}
		if (location1.pathname == '/' || location2.pathname == '/') {
			log("difference looks like a homepage path, treat two URLs as same.");
			return true;
		}
	}
	return false;
}

// Arguments
var taskUrl = system.args[1];
var outputFile = system.args[2];
var timeout = system.args[3];
var imageFile = system.args[4];
var urlSettings = null;
var tryDifferentDeviceAfterFail = true;
var actionCode = null;
var actionTimeout = 0;
if (system.args[1] == '-f') {
	try {
		console.log("Loading configurations from " + system.args[2]);
		var taskJson = JSON.parse(fs.read(system.args[2]));
		taskUrl = taskJson.url;
		outputFile = taskJson.html;
		timeout = taskJson.timeout;
		imageFile = taskJson.image;
		urlSettings = taskJson.settings;
		actionCode = taskJson.action;
		if (urlSettings != null) {
			console.log("Phantomjs page.open settings is load.");
			if (typeof urlSettings.data === 'string' || urlSettings instanceof String)
				;
			else
				urlSettings.data = JSON.stringify(urlSettings.data);
			console.log(JSON.stringify(urlSettings, null, "    "));
		}
		if (actionCode != null) {
			if (typeof actionCode === 'object' ) {
				var str = "";
				for (var i = 0; i < actionCode.length; i++) {
					str = str + actionCode[i] + "\n";
				}
				actionCode = str;
			}
			actionCode = "actionCode = " + actionCode;
			console.log("Post load action():" + actionCode);
			actionCode = eval(actionCode);
			actionTimeout = taskJson.action_time;
		}
		tryDifferentDeviceAfterFail = taskJson.switch_device_after_fail;
		if (tryDifferentDeviceAfterFail == null)
			tryDifferentDeviceAfterFail = true;
		console.log(taskUrl);
	} catch (err) {
		console.log(err);
		phantom.exit(-1);
	}
}

// ENCODE url to for further comparasion.
// NON-ASCII code in URL would lead error in checking status finished.
taskUrl = encodeURI(taskUrl);

// Parse args.
if (taskUrl.indexOf('/') == 0 || taskUrl.indexOf('.') == 0)
	taskUrl = 'file://' + fs.absolute(taskUrl);
try {
	timeout = parseInt(timeout);
	// Timeout for single resource.
    page.settings.resourceTimeout = timeout;
} catch (err) { timeout = null; }
log("Timeout: " + timeout);
var taskDomain = getLocation(taskUrl).hostname.split('.');
taskDomain = taskDomain[taskDomain.length - 2] + '.' + taskDomain[taskDomain.length - 1];
log("Task domain: " + taskDomain);
if (imageFile == null)
	page.settings.loadImages = false;
else
	log("Save image: " + imageFile);

// Init state.
var currentTaskUrl = taskUrl;
var appearredWindowLocation = [];
var history = {};
var maxResponseId = 0;
var taskFinished = false;

// Default user agent.
desktopUserAgent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36';
iPadUserAgent = 'Mozilla/5.0 (iPad; CPU OS 8_1_3 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Version/8.0 Mobile/12B466 Safari/600.1.4';

// Default functions.
page.onAlert = function(msg) {
    log('ALERT: ' + msg);
};
page.onClosing = function(closingPage) {
    log('The page is closing! URL: ' + closingPage.url);
};
page.onConsoleMessage = function(msg, lineNum, sourceId) {
    log('CONSOLE: ' + msg + ' (from line #' + lineNum + ' in "' + sourceId + '")');
};
page.onError = function(msg, trace) {
    var msgStack = ['PAGE ERROR: ' + msg];
    if (trace && trace.length) {
        msgStack.push('TRACE:');
        trace.forEach(function(t) {
            msgStack.push(' -> ' + t.file + ': ' + t.line + (t.function ? ' (in function "' + t.function +'")' : ''));
        });
    }
    log(msgStack.join('\n'));
};
phantom.onError = function(msg, trace) {
	var msgStack = ['PHANTOM ERROR: ' + msg];
	if (trace && trace.length) {
		msgStack.push('TRACE:');
		trace.forEach(function(t) {
			msgStack.push(' -> ' + (t.file || t.sourceURL) + ': ' + t.line + (t.function ? ' (in function ' + t.function +')' : ''));
		});
	}
	log(msgStack.join('\n'));
}
// Phantomjs is now leaving currentUrl to a new unknown page.
page.onLoadStarted = function() {
    var currentUrl = page.evaluate(function() {
        return window.location.href;
    });
	if (currentUrl == 'about:blank') return;
	if (currentUrl == null) return;
	log('Phantomjs is now leaving :' + currentUrl);
    log('task:' + currentTaskUrl);
    log('history:' + JSON.stringify(history));
	if (history[currentUrl] == null) {
		history[currentUrl] = 1;
    	log('history added.');
		currentTaskUrl = null;
	} else {
	    log('Repeat loading history, call pageLoadFinished(success).');
		pageLoadFinished(currentUrl, "success");
	}
};
page.onLoadFinished = function(status) {
    var currentUrl = page.evaluate(function() {
        return window.location.href;
    });
	pageLoadFinished(currentUrl, status);
}

pageLoadFinished = function(currentUrl, status) {
    log('pageLoadFinished():' + status + " url:\n" + currentUrl + "\ncurrentTaskUrl:\n" + currentTaskUrl +  "\nhistory:" + JSON.stringify(history));
	// FIRST THING: record currentUrl if it is equal to currentTaskUrl
	if (compareUrl(currentUrl, currentTaskUrl)) {
		history[currentUrl] = 1;
		history[currentTaskUrl] = 1;
	}
	// Ignore if currentUrl is not recorded.
	if (history[currentUrl] == null) {
		return;
	}

	var success = (status === "success");
	// If all history tasks are finished and urrentTaskUrl is null,
	// mark as finished.
	if (currentTaskUrl == null) {
		var allFinished = true;
		var keyCt = 0;
		for (var key in history) {
			keyCt += 1;
			if (history[key] != 1) {
				allFinished = false;
				break;
			}
		}
		if (keyCt > 0 && allFinished == true) {
			log("currentTaskUrl is NULL, " +
					keyCt + " history paths are finished, so it is finished");
			taskFinished = true;
			return postLoadAction();
		}
	}

	// Whether success or not, always wait for 5 second to check whether phantomjs is redirected to a new page.
	var oldHistory = JSON.stringify(history);
	log("Wait 5s to check if history will be updated: " + oldHistory);
	setTimeout(function(){
		if (oldHistory != JSON.stringify(history)) {
    		log("history has been updated: " + history);
		} else if (currentTaskUrl != null && history[currentTaskUrl] == null) {
    		log("history unchanged, but a new task is running:" + currentTaskUrl);
		} else {
    		log("history unchanged, task finised.");
			taskFinished = true;
			if (success) {
    			log("Finished with success.");
				return postLoadAction();
			} else {
    			log("Render failed. Invoke retryWithAnotherAgent() after 2s.");
				setTimeout(function(){
					retryWithAnotherAgent(success);
				}, 2000);
			}
			return;
		}
	}, 5000);
};
page.onResourceRequested = function(requestData, networkRequest) {
	var u = getLocation(response.url);
	var path = u.pathname;
	var domain = u.hostname;
    log('    ----> Request (#' + requestData.id + '): ' + requestData.method + "\t" + requestData.url);
    if (requestData.id > 1024) {
        log('Abort: request too many resources, use null file instead!');
        networkRequest.changeUrl('null.js'); 
    }
	// Set page request in same domain as currentTaskUrl.
	if (path.endsWith('.js') || path.endsWith('.css'))
		return;
	if (domain.contains(taskDomain) == false)
		return;
	if (currentTaskUrl == null) {
		currentTaskUrl = response.url;
	    log('Current task url is changed: ' + currentTaskUrl)
	}
};

page.onResourceReceived = function(response) {
	var u = getLocation(response.url);
	var path = u.pathname;
	var domain = u.hostname;
    var currentUrl = page.evaluate(function() {
        return window.location.href;
    });
	// There might be several redirections, 
	// the firstly appearred URL is the real task URL.
	if (currentUrl != null && currentUrl != 'about:blank') {
		if (appearredWindowLocation.length == 0) {
			// First appeared
			if (currentTaskUrl != currentUrl) {
				log("Looks like real task URL is " + currentUrl);
				currentTaskUrl = currentUrl;
			}
			appearredWindowLocation.push(currentUrl);
		}
	}
    log('    <<<<< Receive (#' + response.id  + '): \t' + response.url);
	if (maxResponseId < response.id)
		maxResponseId = response.id;
	if (path.endsWith('.js') || path.endsWith('.css'))
		return;
	if (domain.contains(taskDomain) == false)
		return;
	if (currentTaskUrl == null) {
		currentTaskUrl = response.url;
	    log('Task url changed to be: ' + currentTaskUrl)
	}
};
page.onResourceTimeout = function(e) {
    log('Timeout when loading URL:' + e.url);
    log('Error code: ' + e.errorCode + '\nDescription: ' + e.errorString);
    if (compareUrl(e.url, currentTaskUrl)) {
        log("Main task timeout: " + currentTaskUrl);
		pageLoadFinished(currentTaskUrl, "fail");
    }
};
page.onResourceError = function(resourceError) {
	log('    XXXXX Error   (#' + resourceError.id  + '): \t' + resourceError.url);
	log("Error : " + JSON.stringify(resourceError));
    if (compareUrl(resourceError.url, currentTaskUrl)) {
        log("Current task url resource error: " + currentTaskUrl);
		pageLoadFinished(currentTaskUrl, "fail");
    }
}

var postLoadAction = function() {
	var waitTime = 0;
	if (actionCode != null) {
		waitTime = actionTimeout * 1000;
		log("Set taskFinished false, eval action(), timeout = " + waitTime);
		taskFinished = false;
		page.evaluate(actionCode);
	}
	setTimeout(lastAction, waitTime);
}
var lastAction = function() {
	if (outputFile != null)
		fs.write(outputFile, page.content, 'w');
	if (imageFile != null)
		page.render(imageFile);
	phantom.exit(0);
}

// Use iPad user agent first, if failed, use desktop user agent to try again.
var hasRetry = false;
var retryWithAnotherAgent = function(status) {
	log("retryWithAnotherAgent() invoked, status:" + status);
	if (!taskFinished)
		return log("retryWithAnotherAgent() aborted: task not finished.");
	// Task finished below.
	if (hasRetry == true) {
		log("retryWithAnotherAgent() aborted: not first invoke, exit with status:" + status);
	    if (status === "success")
	        return postLoadAction();
        phantom.exit(1);
		return;
	}
	hasRetry = true;
    if (status === "success")
		return postLoadAction();
	// Failed and do not try to switch device.
	if (tryDifferentDeviceAfterFail == false)
        return phantom.exit(1);
	// Wait time must be larger than 5s
	log("================== USE IPAD USER AGENT TO TRY AGAIN AFTER 6 seconds ================");
	setTimeout(function(){
		log("================== USE IPAD USER AGENT TO TRY AGAIN ================");
		page.settings.userAgent = iPadUserAgent;
		taskFinished = false;
		currentTaskUrl = system.args[1];
		history = {};
		var cb = function(status){
			if (!taskFinished) return;
	    	log('page.open callback for ipad user agent :' + status);
		    if (status === "success")
		        return postLoadAction();
	        phantom.exit(1);
		}
		if (urlSettings == null)
			page.open(taskUrl, cb);
		else
			page.open(taskUrl, urlSettings, cb);
	}, 6000);
}

page.settings.userAgent = desktopUserAgent;
if (urlSettings == null)
	page.open(taskUrl, retryWithAnotherAgent);
else
	page.open(taskUrl, urlSettings, retryWithAnotherAgent);
