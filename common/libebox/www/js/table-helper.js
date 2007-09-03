// TODO 
//      - Use Form.serialize stuff to get params
//      - Refactor addNewRow and actionClicked, they do almost the same
//      - Implement a generic function for the onComplete stage

function cleanError(table)
{
	$('error_' + table).innerHTML = "";
}

function addNewRow(url, table, fields, directory)
{
	var pars = 'action=add&tablename=' + table + '&directory=' + directory + '&';

  	pars += '&filter=' + inputValue(table + '_filter');
  	pars += '&pageSize=' + inputValue(table + '_pageSize');
	
	cleanError(table);

	for (var i = 0; i < fields.length; i++) {
		var field = fields[i];
		//var value = $F(table + '_' + field);
		var value = inputValue(table + '_' + field);
		if (value) {
		  if (pars.length != 0) {
				pars += '&';
			}
			pars += field + '=' + value;
		}
	}

	var MyAjax = new Ajax.Updater(
		{
		success: table,
		failure: 'error_' + table 
		},
		url,
		{
			method: 'post',
			parameters: pars,
			asyncrhonous: false,
			evalScripts: true,
			onComplete: function(t) {
			  stripe('dataTable', '#ecf5da', '#ffffff'); 
			},
			onFailure: function(t) {
			  restoreHidden('buttons');
			}
		});

	setLoading('buttons', true);

}

function changeRow(url, table, fields, directory, id, page)
{
	var pars = 'action=edit&tablename=' + table + '&directory='
                   + directory + '&id=' + id + '&';
	if ( page != undefined ) {
	   pars += '&page=' + page;
	 }
        if ( page != undefined ) {
          pars += '&page=' + page;
        }
  	pars += '&filter=' + inputValue(table + '_filter');
  	pars += '&pageSize=' + inputValue(table + '_pageSize');

	cleanError(table);
	
	for (var i = 0; i < fields.length; i++) {
		var field = fields[i];
		var value = inputValue(table + '_' + field);
		if (value) {
			if (pars.length != 0) {
				pars += '&';
			}
			pars += field + '=' + value;
		}
	}

	var MyAjax = new Ajax.Updater(
		{
			success: table,
			failure: 'error_' + table 
		},
		url,
		{
			method: 'post',
			parameters: pars,
			asyncrhonous: false,
			evalScripts: true,
			onComplete: function(t) { 
			  highlightRow( id, false);
			  stripe('dataTable', '#ecf5da', '#ffffff');
			},
			onFailure: function(t) {
			  restoreHidden('buttons');
			}
		});

	 setLoading('buttons', true);

}


/*
Function: actionClicked

        Callback function when an action on the table is clicked

Parameters:

        url - the CGI URL to call to do the action
	table - the table's name
        action - the action to do (move, del)
	rowId  - the affected row identifier
	paramsAction - an string with the parameters related to the
                       action E.g.: param1=value1&param2=value2 *(Optional)*
	directory - the GConf directory where table is stored

*/

function actionClicked(url, table, action, rowId, paramsAction, directory, page) {

  var pars = '&action=' + action + '&id=' + rowId;

  if ( paramsAction != '' ) {
    pars += '&' + paramsAction;
  }
  if ( page != undefined ) {
    pars += '&page=' + page;
  }

  pars += '&filter=' + inputValue(table + '_filter');
  pars += '&pageSize=' + inputValue(table + '_pageSize');
  pars += '&directory=' + directory + '&tablename=' + table;

  cleanError(table);
	
  var MyAjax = new Ajax.Updater(
	    {
		success: table,
		failure: 'error_' + table 
	    },
	    url,
	    {
		method: 'post',
		parameters: pars,
		asyncrhonous: false,
		evalScripts: true,
		onComplete: function(t) {
		  stripe('dataTable', '#ecf5da', '#ffffff');
		},
		onFailure: function(t) {
		  restoreHidden('actionsCell_' + rowId);
		}
	    });

  if ( action == 'del' ) {
    setLoading('actionsCell_' + rowId);
  }
  else if ( action == 'move' ) {
    setLoading('actionsCell_' + rowId);
  }

}

function changeView(url, table, directory, action, id, page)
{
	var pars = 'action=' + action + '&tablename=' + table + '&directory=' + directory + '&editid=' + id;
	
	pars += '&filter=' + inputValue(table + '_filter');
  	pars += '&pageSize=' + inputValue(table + '_pageSize');
	pars += '&page=' + page;

	cleanError(table);
	
	var MyAjax = new Ajax.Updater(
		{
			success: table,
			failure: 'error_' + table 
		},
		url,
		{
			method: 'post',
			parameters: pars,
			asyncrhonous: false,
			evalScripts: true,
			onComplete: function(t) { 
			  // Highlight the element
              if (id != undefined) {
			    highlightRow(id, true);
              }
			  // Stripe again the table
			  stripe('dataTable', '#ecf5da', '#ffffff');
			  if ( action == 'changeEdit' ) {
			    restoreHidden('actionsCell_' + id);
			  }
			},
			onFailure: function(t) {
			  if ( action == 'changeAdd' ) {
			    restoreHidden('creatingForm');
			  }
			  else if ( action == 'changeList' ) {
			    restoreHidden('buttons');
			  }
			  else if ( action == 'changeEdit' ) {
			    restoreHidden('actionsCell_' + id);
			  }
			}
			
		});

	if ( action == 'changeAdd' ) {
	  setLoading('creatingForm', true);
	}
	else if ( action == 'changeList' ) {
	  setLoading('buttons', true);
	}
	else if ( action == 'changeEdit' ) {
	  setLoading('actionsCell_' + id, true);
	}

}

/*
Function: hangTable

        Hang a table under the given identifier via AJAX request
	replacing all HTML content. The parameters to the HTTP request
	are passed by an HTML form.

Parameters:

        successId - div identifier where the new table will be on on success
	errorId - div identifier
        url - the URL where the CGI which generates the HTML is placed
	formId - form identifier which has the parameters to pass to the CGI
        loadingId - String element identifier that it will substitute by the loading image
        *(Optional)* Default: 'loadingTable'

*/
function hangTable(successId, errorId, url, formId, loadingId)
{

  // Cleaning manually
  $(errorId).innerHTML = "";

  if ( ! loadingId ) {
    loadingId = 'loadingTable';
  }

  var ajaxUpdate = new Ajax.Updater( 
  {
  success: successId,
  failure: errorId 
  },
  url,
      {
	method: 'post',
	parameters: Form.serialize(formId, true), // The parameters are taken from the form
	asynchronous: true,
	onComplete: function(t) {
	  restoreHidden(loadingId);
	}
      }
  );
 
  setLoading(loadingId);
 
}

/*
Function: showSelected

        Show the HTML setter selected in select

Parameters:

        selectId - the select identifier
	nodeId   - the HTML node where all setters hang
	tableName - the table name to build the id

*/
function showSelected (selectId, nodeId, tableName)
{

  var selectedIdx =  $(selectId).selectedIndex;

  // If there is any selected value
  if ( selectedIdx != -1 ) {
    var selectedValue = $(selectId).options[selectedIdx].value;
    // Build the value
    selectedValue = tableName + "_" + selectedValue;

    // Set every child as hidden except for the selected
    for(var idx = 0; idx < $(nodeId).childNodes.length; idx++) {
      var node = $(nodeId).childNodes[idx];
      // I'd like to use constant but in IE 6 simply they don't exist
      if ( node.nodeType == 1 /* Node.ELEMENT_NODE */ ) {
	if ( node.id == selectedValue ) {
	  show( node.id );
	} 
	else {
	  hide( node.id );
	}
      }
    }
  }

}

/*
Function: showPort

      Show port if it's necessary given a protocol

Parameters:

        protocolSelectId - the select identifier which the protocol is chosen
	portId   - the identifier where port is going to be set
	protocols - the list of protocols which need a port to be set

*/
function showPort(protocolSelectId, portId, protocols)
{

  var selectedIdx = $(protocolSelectId).selectedIndex;
  var selectedValue = $(protocolSelectId).options[selectedIdx].value;

  var found = false;
  // Search the selected value into the array to know if it needs a port or not
  for ( var idx = 0; idx < protocols.length && ! found; idx++) {
    if ( selectedValue == protocols[idx] ) {
      found = true;
      show(portId);
    }
  }

  if (! found) {
    hide(portId);
  }

}

/* TODO: showPortRange and showPort do things in common
	 like showing/hiding elments depending on which value
	 is selected elsewhere. We should refactor this
	 and provide a generic function to do that. Logic should
	 come from model and translated in javascript.
/*
Function: showPortRange

    Show/Hide elements in PortRange view

Parameters:

    id - the select identifier which the protocol is chosen

*/
function showPortRange(id)
{

  var selectId = id + "_range_type";
  var selectedIdx = $(selectId).selectedIndex;
  var selectedValue = $(selectId).options[selectedIdx].value;

  if ( selectedValue == "range") {
    show(id + "_range");
    hide(id + "_single");
    $(id + "_single_port").value = "";
  } else if (selectedValue == "single") {
    hide(id + "_range");
    show(id + "_single");
    $(id + "_to_port").value = "";
    $(id + "_from_port").value = "";
  } else {
    hide(id + "_range");
    hide(id + "_single");
    $(id + "_to_port").value = "";
    $(id + "_from_port").value = "";
    $(id + "_single_port").value = "";
  }
}

/*
Function: setLoading

        Set the loading icon on the given HTML element erasing
        everything which were there

Parameters:

        elementId - the element identifier
	isSaved   - boolean to indicate if the inner HTML should be saved
	at *hiddenDiv* in order to be rescued afterwards *(Optional)*

*/
function setLoading (elementId, isSaved)
{

  if ( isSaved ) {
    $('hiddenDiv').innerHTML = $(elementId).innerHTML;
  }

  $(elementId).innerHTML = "<img src='/data/images/ajax-loader.gif' " +
                           "alt='loading...' class='tcenter'/>";

}

/*
Function: restoreHidden

        Restore HTML stored in *hiddenDiv*

Parameters:

        elementId - the element identifier where to restore the HTML hidden

*/
function restoreHidden (elementId)
{

  if ( $('hiddenDiv').innerHTML != '' ) {
    $(elementId).innerHTML = $('hiddenDiv').innerHTML;
  }

  // Remove the loading image if any
  if ( $(elementId).firstChild ) {
    if ( $(elementId).firstChild.alt == 'loading...' ) {
      $(elementId).innerHTML = '';
    }
  }

  $('hiddenDiv').innerHTML = '';

}

/*
Function: disableInput

        Disable all inputs attached as children to the given element

Parameters:

        elementId - the element identifier where all input elements hang

*/
function disableInput(elementId)
{

  var children = $(elementId).childNodes;

  for (var idx = 0; idx < children.length; idx++) {
    // I'd like to use constant but in IE 6 simply they don't exist
    node = children[idx];
    if ( node.nodeType == 1 /* Node.ELEMENT_NODE */ ) {
      //      if ( typeof node == "HTMLInputElement" ) {
	
	node.disable = true;
	//}
    }
  }

}

/*
Function: highlightRow

        Enable/Disable a hightlight over an element on the table

Parameters:

        elementId - the row identifier to highlight
	enable    - if enables/disables the highlight *(Optional)*
	            Default value: true

*/
function highlightRow(elementId, enable)
{

  // If enable has value null or undefined
  if ( enable == null) {
    enable = true;
  }
  if (enable) {
    // Highlight the element putting the CSS class which does so
    Element.addClassName(elementId, "highlight");
  }
  else {
    Element.removeClassName(elementId, "highlight");
  }

}

/*
Function: inputValue

	Use $F() to return an input value. It firstly checks
	using $() if the id exits

Parameters:

	elementId - the input element to fetch the value from

Returns:

	input value if it exits, otherwise empty string
*/
function inputValue(elementId) {

	if ($(elementId)) {
		return $F(elementId);
	} else {
		return '';
	}
}

