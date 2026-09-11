import QtQuick
import QtTest
import "../../services/FolderLogic.js" as F
TestCase {
    name: "FolderSignedWire"
    function wire(times, names) {
        return {version:1,generation:1,token:"signed",status:"ok",complete:true,inspected:times.length,
            receipt:{generation:1,token:"signed",inspected:times.length,complete:true},
            total:times.length,omitted:0,rootIdentity:{device:"1",inode:"2"},
            entries:times.map((t,i)=>({name:names ? names[i] : "n"+i,path:"/owned/"+(names ? names[i] : "n"+i),
                type:"file",size:1,mtimeNs:t,relativeTime:"just now",iconCategory:"document"}))};
    }
    function normalize(w) { return F.normalize(w,{path:"/owned",generation:1,token:"signed"}); }
    function test_arbitrary_precision_signed_order() {
        const times=["999999999999999999999999999999999999999", "9007199254740993", "9007199254740992", "1", "0", "-1", "-9", "-10", "-9007199254740992", "-9007199254740993", "-999999999999999999999999999999999999999"];
        compare(normalize(wire(times)).entries.map(e=>e.mtimeNs), times);
        for(let i=1;i<times.length;++i) {
            let threw=false;try { normalize(wire([times[i],times[i-1]])); } catch(e) { threw=true; }
            verify(threw, "reject inverted pair "+i);
        }
    }
    function test_canonical_signed_wire_only() {
        for(const t of ["-0","+1","01","-01","1.0","1e9"," 1","1\n",1,null,"-","", "--1"]) {
            let threw=false;try { normalize(wire([t])); } catch(e) { threw=true; }
            verify(threw, "reject noncanonical "+JSON.stringify(t));
        }
        const w=wire(["-1"]);w.rootIdentity.inode="-1";
        let threw=false;try { normalize(w); } catch(e) { threw=true; }verify(threw);
    }
    function test_negative_unicode_ties() {
        compare(normalize(wire(["-2","-2"],["\ue000","\ud800\udc00"])).entries.length,2);
        let threw=false;try { normalize(wire(["-2","-2"],["\ud800\udc00","\ue000"])); } catch(e) { threw=true; }verify(threw);
    }
}
