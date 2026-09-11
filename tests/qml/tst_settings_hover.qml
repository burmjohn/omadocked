import QtQuick
import QtTest
TestCase {
 id: test; name: "SettingsHover"; visible:true; when:windowShown
 width:1800; height:800
 function test_stationary_data() {
  const rows=[];
  for (const names of [true,false])
   for (const point of ["center","left","left-inner","shelf-edge","boundary","boundary-inner","above","top-edge"])
    rows.push({tag:point+"-names-"+names,point:point,names:names});
  return rows;
 }
 function test_stationary(data) {
  const c=Qt.createComponent("../../ui/DockView.qml"); compare(c.status,Component.Ready,c.errorString());
  const apps=[]; for(let i=0;i<18;++i) apps.push({id:"fixture"+i,name:"Fixture",icon:"",running:true,active:false});
  const d=createTemporaryObject(c,test,{applications:apps,appsManaged:true,autoHide:true,iconSize:34,zoomSize:140,waveWidth:25,showAppNames:data.names,icons:({menu:"file:///usr/share/icons/breeze/apps/32/preferences-system.svg"})});
  d.shelfEntered(); verify(waitForRendering(d));
  mouseMove(d,d.rowX+d.slotSize/2,d.height-30); wait(250);
  const s=d.renderedSlots[0];
  const x=data.point==="left-inner"?s.left+8:data.point==="boundary-inner"?s.right-8:data.point==="left"?s.left+1:data.point==="shelf-edge"?d.shelfRect.x+1:data.point==="boundary"?s.right-1:s.center;
  const y=data.point==="above"?d.rowY-10:data.point==="top-edge"?d.height-d.dockHeight+1:d.height-30;
  mouseMove(d,x,y); wait(700); // Include the 350ms hide delay plus 140ms slide at the outer shelf edge.
  const art=findChild(d,"art-menu"),tip=findChild(d,"app-tooltip");
  compare(art.status,Image.Ready);
  let owners=0,pointers=0,scales=0,inputs=0,tips=0;
  d.hoveredIndexChanged.connect(function(){++owners;});
  d.pointerXChanged.connect(function(){++pointers;});
  art.scaleChanged.connect(function(){++scales;});
  d.inputRectsChanged.connect(function(){++inputs;});
  d.tooltipIndexChanged.connect(function(){++tips;});
  const start=JSON.stringify({slot:d.renderedSlots[0],input:d.inputRects,scale:art.scale,owner:d.hoveredIndex});
  for(let n=0;n<15;++n) {d.applications=apps.map((a,i)=>Object.assign({},a,{active:i===n%2}));wait(100);verify(findChild(d,"art-menu")===art);}
  console.log(data.tag,JSON.stringify({x:x,y:y,owners:owners,pointers:pointers,scales:scales,inputs:inputs,tips:tips,owner:d.hoveredIndex,caption:tip.captionId,slot:d.renderedSlots[0],artY:art.y,source:String(art.source),input:d.inputRects}));
  compare(pointers,0);compare(owners,0);compare(scales,0);
  compare(JSON.stringify({slot:d.renderedSlots[0],input:d.inputRects,scale:art.scale,owner:d.hoveredIndex}),start);
  if(d.hoveredIndex===0){compare(d.tooltipIndex,0);compare(tip.captionId,"menu");}
 }
}
