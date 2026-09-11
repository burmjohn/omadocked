import QtQuick
import QtQuick.Controls
import QtTest
import "../../ui"
TestCase {
 id: test; name:"FolderRepairUI"; when:windowShown; visible:true; width:800; height:800
 Component { id: viewComponent; DockView { reducedMotion:true; autoHide:false; homePath:"/tmp/owned" } }
 Component { id: chooserComponent; FolderChooser { width:276; height:406 } }
 Component { id: settingsComponent; FolderSettings { width:276; homePath:"/tmp/owned" } }
 SignalSpy { id: actions; signalName:"actionRequested" }
 SignalSpy { id: additions; signalName:"addRequested" }
 SignalSpy { id: browse; signalName:"folderBrowseRequested" }
 function contained(item, scroll) {
  const p=item.mapToItem(scroll,0,0);
  verify(p.y>=-0.01 && p.y+item.height<=scroll.height+0.01, "focus outside viewport: "+p.y+" / "+scroll.height);
 }
 function test_add_keyboard_data() {
  return [{tag:"return",key:Qt.Key_Return},{tag:"enter",key:Qt.Key_Enter},{tag:"space",key:Qt.Key_Space}];
 }
 function test_add_keyboard(data) {
  const s=createTemporaryObject(settingsComponent,test,{scannedPath:"/tmp/owned",result:{complete:true,entries:[]}});
  s.beginSelection(false);additions.target=s;additions.clear();
  const b=findChild(s,"folder-picker-accept");b.forceActiveFocus();
  verify(b.activeFocus);verify(b.enabled);
  const accept=()=>s.saveAccepted(41);s.addRequested.connect(accept);
  keyClick(data.key);
  compare(additions.count,1);compare(additions.signalArguments[0][0],"/tmp/owned");
  compare(s.pendingTransactionId,41);compare(s.draftPending,true);
  keyClick(data.key);compare(additions.count,1,"pending must reject duplicate keyboard input");
  s.saveResult(42,true);compare(s.pendingTransactionId,41);
  s.saveResult(41,false);compare(s.selecting,true);compare(s.pendingTransactionId,0);
  s.addRequested.disconnect(accept);
  s.busy=true;b.forceActiveFocus();keyClick(data.key);compare(additions.count,1);
 }
 function test_keyboard_forward_backward_enter_escape_dynamic_rows() {
  const v=createTemporaryObject(viewComponent,test);v.settingsOpen=true;wait(20);
  const s=findChild(v,"folder-settings");s.beginSelection(true);
  const field=findChild(s,"folder-picker-path"), scroll=findChild(v,"settings-scroll");
  browse.target=v;browse.clear();
  for(let i=0;i<80 && !field.activeFocus;++i) { keyClick(Qt.Key_Tab);wait(1); }
  compare(field.activeFocus,true);contained(field,scroll);
  keyClick(Qt.Key_Return);compare(browse.count,1);
  v.folderScannedPath=field.text;v.folderResult={complete:true,entries:[]};wait(10);
  const add=findChild(s,"folder-picker-accept");
  for(let i=0;i<12 && !add.activeFocus;++i) { keyClick(Qt.Key_Tab);wait(1); }
  compare(add.activeFocus,true);contained(add,scroll);
  v.folderResult={complete:true,entries:Array.from({length:16},(_,i)=>({type:"directory",label:"Owned "+i,path:"/tmp/owned/"+i}))};
  wait(20);compare(add.activeFocus,true);contained(add,scroll);
  for(let i=0;i<30 && !field.activeFocus;++i) { keyClick(Qt.Key_Backtab);wait(1); }
  compare(field.activeFocus,true);contained(field,scroll);
  keyClick(Qt.Key_Escape);wait(20);compare(s.selecting,false);
  v.settingsOpen=true;s.beginSelection(false);compare(field.text,"/tmp/owned");
 }
 function test_compact_picker_all_navigation_children_fit() {
  const s=createTemporaryObject(settingsComponent,test,{width:220});s.beginSelection(false);wait(10);
  const field=findChild(s,"folder-picker-path"), nav=field.parent.children[1];
  for(const b of nav.children) { verify(b.x>=0);verify(b.x+b.width<=s.width);verify(b.y+b.height<=nav.height); }
 }
 function test_manager_press_generation_replacement_rejects_release() {
  const c=createTemporaryObject(chooserComponent,test,{generation:1,result:{complete:true,entries:[]}});
  actions.target=c;actions.clear();const b=findChild(c,"folder-manager");
  mousePress(b,30,16);compare(b.pressed,true);
  c.generation=2;c.busy=true;c.result={};wait(10);c.result={complete:true,entries:[]};c.busy=false;
  mouseRelease(b,30,16);
  compare(actions.count,0,"manager release must not activate a different scan generation");
 }
 function test_terminal_press_generation_replacement_rejects_release() {
  const c=createTemporaryObject(chooserComponent,test,{generation:1,result:{complete:true,entries:[]}});
  actions.target=c;actions.clear();const b=findChild(c,"folder-terminal");
  mousePress(b,30,16);compare(b.pressed,true);
  c.generation=2;c.busy=true;c.result={};wait(10);c.result={complete:true,entries:[]};c.busy=false;mouseRelease(b,30,16);
  compare(actions.count,0,"terminal release must not activate a different scan generation");
 }
 function test_picker_rejected_save_retains_draft() {
  const s=createTemporaryObject(settingsComponent,test,{scannedPath:"/tmp/owned",result:{complete:true,entries:[]}});
  additions.target=s;additions.clear();const rev=s.beginSelection(false);
  // A receiver with unavailable storage cannot accept a persistence transaction.
  // There is intentionally no success acknowledgement, as on synchronous rejection.
  verify(s.acceptSelection(rev,"/tmp/owned"));compare(additions.count,1);
  compare(s.selecting,true,"picker must retain its draft until durable save succeeds");
 }
 function test_picker_focus_scrolls_into_visible_settings() {
  const v=createTemporaryObject(viewComponent,test);v.settingsOpen=true;wait(30);
  const s=findChild(v,"folder-settings");s.beginSelection(true);
  const field=findChild(v,"folder-picker-path");
  for(let i=0;i<80 && !field.activeFocus;++i) keyClick(Qt.Key_Tab);
  wait(30);compare(field.activeFocus,true);
  const scroll=findChild(v,"settings-scroll");const point=field.mapToItem(scroll,0,0);
  verify(point.y>=0 && point.y+field.height<=scroll.height,"focused path y="+point.y+" height="+field.height+" viewport="+scroll.height);
 }
 function test_failed_preset_does_not_show_unsaved_check() {
  const s=createTemporaryObject(settingsComponent,test);wait(10);
  const flow=s.children[1];const b=flow.children[0];
  compare(b.text,"Downloads");compare(b.checked,false);
  mouseClick(b,30,b.height/2);compare(s.records.length,0);
  compare(b.checked,false,"rejected pin save must not remain visually checked");
 }
 function test_accessible_entry_and_launcher_path_invalidation() {
  const id="launcher:11111111-1111-4111-8111-111111111111";
  const record={id:id,kind:"folder",name:"Owned",target:"/tmp/owned",enabled:true};
  const v=createTemporaryObject(viewComponent,test,{applications:[{id:id,kind:"folder",name:"Owned",enabled:true,canEdit:true}],launcherRecords:[record]});
  v.folderResult={complete:true,entries:[{path:"/tmp/owned/a",label:"A",type:"file",size:1,relativeTime:"just now",icon:""}]};
  verify(v.openFolder(id));const c=v.activeFolderChooser;actions.target=c;actions.clear();
  const list=findChild(c,"folder-list");list.forceLayout();tryVerify(()=>list.itemAtIndex(0)!==null);
  list.itemAtIndex(0).Accessible.pressAction();compare(actions.count,1);
  v.launcherRecords=[Object.assign({},record,{target:"/tmp/replaced"})];
  compare(v.folderChooserOpen,false);tryCompare(v,"activeFolderChooser",null);
  verify(v.openFolder(id));v.launcherRecords=[];compare(v.folderChooserOpen,false);
 }
 function test_picker_controls_fit_compact_width() {
  const s=createTemporaryObject(settingsComponent,test,{width:220});s.beginSelection(false);wait(10);
  const f=findChild(s,"folder-picker-path");const column=f.parent;
  const row=column.children[1];
  verify(row.width<=s.width,"picker navigation width "+row.width+" exceeds "+s.width);
 }
}
