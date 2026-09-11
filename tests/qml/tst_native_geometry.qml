import QtQuick
import QtTest
import "../../core/DockLogic.js" as Logic

TestCase {
    name: "NativePopupGeometry"
    function test_pixelQuantizationDoesNotBlockFocus() {
        verify(Logic.nativeSizeMatches(1048, 323, 1047, 323));
        verify(Logic.nativeSizeMatches(1047, 323, 1047, 323));
        verify(Logic.nativeSizeMatches(1046, 322, 1047, 323));
        verify(!Logic.nativeSizeMatches(1047, 131, 1047, 323));
        verify(!Logic.nativeSizeMatches(1049, 323, 1047, 323));
        verify(!Logic.nativeSizeMatches(1047, 325, 1047, 323));
        verify(!Logic.nativeSizeMatches(0, 0, 0, 0));
        verify(!Logic.nativeSizeMatches(NaN, 323, 1047, 323));
    }
}
