package com.aspauldingcode.wawona

import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.CorrectionInfo
import android.view.inputmethod.CursorAnchorInfo
import android.view.inputmethod.InputConnection

/**
 * InputConnection that routes Android IME text (including emoji) to the
 * Wawona compositor via JNI → Rust → Wayland text-input-v3.
 *
 * The system IME calls commitText() for committed text (including emoji
 * selections), setComposingText() for pre-edit / composition, and
 * deleteSurroundingText() for backspace-like operations.
 *
 * When Text Assist is enabled, the IME also sends autocorrections via
 * commitCorrection() and richer composition sequences.
 */
class WawonaInputConnection(
    private val view: View,
    fullEditor: Boolean
) : BaseInputConnection(view, fullEditor) {

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
        if (text == null || text.isEmpty()) return true
        WLog.d("INPUT", "commitText: \"$text\" cursorPos=$newCursorPosition")
        // Clear any preedit first, then commit the final text
        WawonaNative.nativePreeditText("", 0, 0)
        WawonaNative.nativeCommitText(text.toString())
        return true
    }

    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
        val str = text?.toString() ?: ""
        WLog.d("INPUT", "setComposingText: \"$str\" cursorPos=$newCursorPosition")
        WawonaNative.nativePreeditText(str, 0, str.length)
        return true
    }

    override fun finishComposingText(): Boolean {
        WLog.d("INPUT", "finishComposingText")
        WawonaNative.nativePreeditText("", 0, 0)
        return true
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
        WLog.d("INPUT", "deleteSurroundingText: before=$beforeLength after=$afterLength")
        WawonaNative.nativeDeleteSurroundingText(beforeLength, afterLength)
        return true
    }

    override fun commitCorrection(correctionInfo: CorrectionInfo?): Boolean {
        if (correctionInfo == null) return true
        val oldText = correctionInfo.oldText?.toString() ?: return true
        val newText = correctionInfo.newText?.toString() ?: return true
        WLog.d("INPUT", "commitCorrection: \"$oldText\" -> \"$newText\" at offset=${correctionInfo.offset}")

        // Delete the old text and commit the corrected replacement.
        // The offset is relative to the composing span, but for text-input-v3
        // we express it as delete_surrounding_text + commit_string.
        val deleteLen = oldText.length
        if (deleteLen > 0) {
            WawonaNative.nativeDeleteSurroundingText(deleteLen, 0)
        }
        WawonaNative.nativeCommitText(newText)
        return true
    }

    override fun performEditorAction(editorAction: Int): Boolean {
        WLog.d("INPUT", "performEditorAction: $editorAction")
        return super.performEditorAction(editorAction)
    }

    override fun requestCursorUpdates(cursorUpdateMode: Int): Boolean {
        WLog.d("INPUT", "requestCursorUpdates: mode=$cursorUpdateMode")
        if (cursorUpdateMode and InputConnection.CURSOR_UPDATE_IMMEDIATE != 0) {
            reportCursorAnchorInfo()
        }
        return true
    }

    private fun reportCursorAnchorInfo() {
        val rect = IntArray(4)
        WawonaNative.nativeGetCursorRect(rect)
        val info = CursorAnchorInfo.Builder()
            .setInsertionMarkerLocation(
                rect[0].toFloat(),
                rect[1].toFloat(),
                (rect[1] + rect[3]).toFloat(),
                (rect[1] + rect[3]).toFloat(),
                CursorAnchorInfo.FLAG_HAS_VISIBLE_REGION
            )
            .build()
        val imm = view.context.getSystemService(
            android.content.Context.INPUT_METHOD_SERVICE
        ) as? android.view.inputmethod.InputMethodManager
        imm?.updateCursorAnchorInfo(view, info)
    }
}
