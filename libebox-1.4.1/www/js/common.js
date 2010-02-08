function getElementByClass(classname) {
	ccollect=new Array()
	var inc=0;
	var alltags=document.getElementsByTagName("*");
	for (i=0; i<alltags.length; i++){
		if (alltags[i].hasClassName(classname))
			ccollect[inc++]=alltags[i];
	}
	return ccollect;
}

function setDefault(){
	elements=getElementByClass("hide");
	var inc=0;
	while (elements[inc]){
		elements[inc].style.display="none";
		inc++;
	}
	inc=0;
	elements=getElementByClass("show");
	while (elements[inc]){
		elements[inc].style.display="inline";
		inc++;
	}
}

function show(id){
	setDefault();
	document.getElementById(id).style.display="block";
	document.getElementById("hideview" + id).style.display="none";
	document.getElementById("showview" + id).style.display="inline";
}

function hide(id){
	setDefault();
}

var shownMenu = "";

function showMenu(name){
	var inc;
	if(shownMenu.length != 0) {
		elements=getElementByClass(shownMenu);
		inc=0;
		while (elements[inc]){
			elements[inc].style.display="none";
			inc++;
		}
	}

	elements=getElementByClass(name);
	inc=0;
	while (elements[inc]){
		elements[inc].style.display="inline";
		inc++;
	}
	shownMenu = name;
}

/*
Function: checkAll

        Check all checkboxes within a HTML element. When the all element
        is checked, the remain elements get disabled. When the all
        element is unchecked, the remain elements get enabled.

Parameters:

        id - identifier where all checkboxs should be checked
        allElementName - name for the all check box 

*/
function checkAll(id, allElementName){

        var form = document.getElementById(id);
	var allbox = form.elements[allElementName];
	for (var i=0;i<form.elements.length;i++)
	{
		var e=form.elements[i];
		if ((e.name != allElementName) && (e.type=='checkbox')) {
			e.checked = allbox.checked;
			e.disabled = allbox.checked;
		}
	}
}

/*
 */
function stripe(theclass,evenColor,oddColor) {
    var tables = getElementByClass(theclass);

    for (var n=0; n<tables.length; n++) {
        var even = false;
        var table = tables[n];
        var tbodies = table.getElementsByTagName("tbody");

        for (var h = 0; h < tbodies.length; h++) {
            var trs = tbodies[h].getElementsByTagName("tr");
            for (var i = 0; i < trs.length; i++) {
	      if (! trs[i].style.backgroundColor && (trs[i].className.indexOf("highlight") == -1)) {
		var tds = trs[i].getElementsByTagName("td");
		for (var j = 0; j < tds.length; j++) {
		  var mytd = tds[j];
		  if (! mytd.style.backgroundColor) {
		    mytd.style.backgroundColor = even ? evenColor : oddColor;
		  }
		}
	      }
	      even =  ! even;
            }
        }
    }
}

/*
Function: selectDefault

        Given a select identifier determine
        whether user has select default option or not.

Parameters:

	selectId - select identifier

Returns:

        true - if user has selected the default value
	false - otherwise

*/
function selectDefault (selectId) {

  if ( $(selectId).selectedIndex == 0 ) {
    return true;
  }
  else {
    return false;
  }

}

/*
Function: hide

        Hide an element

Parameters:

        elementId - the node to show or hide

*/
function hide(elementId)
{

  Element.addClassName(elementId, 'hidden');

}

/*
Function: show

        Show an element

Parameters:

        elementId - the node to show or hide

*/
function show(elementId)
{

  Element.removeClassName(elementId, 'hidden');

}
