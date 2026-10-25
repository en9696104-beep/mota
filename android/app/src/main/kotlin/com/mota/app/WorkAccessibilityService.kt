package com.mota.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.ArrayDeque

/**
 * MOTA 工作台无障碍服务（对应「无障碍权限」档）
 *
 * 能力：手势分发（tap/swipe）、文本输入、屏幕内容读取。
 * 仅在用户于系统设置中手动开启后由系统绑定；[instance] 为 null 即未开启。
 */
class WorkAccessibilityService : AccessibilityService() {

    companion object {
        /** 服务已连接时的单例引用；null 表示未开启（UI 据此引导授权） */
        @Volatile
        var instance: WorkAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 无需事件回调：所有动作由控制端指令主动触发
    }

    override fun onInterrupt() {
        // 系统要求取消反馈时调用；本服务无持续反馈
    }

    /** 点击（路径为零长度线段，duration 50ms） */
    fun tap(x: Float, y: Float, callback: (Boolean) -> Unit) {
        val path = Path().apply { moveTo(x, y) }
        dispatchStroke(path, callback)
    }

    /** 滑动 */
    fun swipe(
        x1: Float, y1: Float, x2: Float, y2: Float,
        durationMs: Long, callback: (Boolean) -> Unit,
    ) {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        dispatchStroke(path, callback, durationMs.coerceAtLeast(16))
    }

    private fun dispatchStroke(path: Path, callback: (Boolean) -> Unit, durationMs: Long = 50) {
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = try {
            GestureDescription.Builder().addStroke(stroke).build()
        } catch (e: Exception) {
            callback(false)
            return
        }
        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) = callback(true)
            override fun onCancelled(gestureDescription: GestureDescription?) = callback(false)
        }, null)
        if (!dispatched) callback(false)
    }

    /**
     * 向当前焦点输入框写入文本。
     * 优先焦点节点；无焦点时退回窗口内第一个可编辑节点。
     */
    fun inputText(text: String): Boolean {
        val node = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: rootInActiveWindow?.let { findFirstEditable(it) }
            ?: return false
        return try {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            val ok = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            if (ok) {
                // 光标移到末尾，方便后续输入
                val sel = Bundle().apply {
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, text.length)
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, text.length)
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, sel)
            }
            ok
        } catch (e: Exception) {
            false
        } finally {
            node.recycle()
        }
    }

    /** 遍历当前窗口节点树，dump 文本与描述（含屏幕坐标） */
    fun readScreen(): String {
        val root = rootInActiveWindow ?: return "(无窗口信息：服务可能刚被系统回收)"
        val lines = ArrayList<String>()
        val seen = HashSet<String>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.poll() ?: continue
            try {
                if (!node.isVisibleToUser) continue
                val label = node.text?.toString()?.takeIf { it.isNotBlank() }
                    ?: node.contentDescription?.toString()?.takeIf { it.isNotBlank() }
                if (label != null) {
                    val rect = Rect().also { node.getBoundsInScreen(it) }
                    val key = "$label@$rect"
                    if (seen.add(key)) {
                        lines.add("$label\t[${rect.left},${rect.top},${rect.right},${rect.bottom}]")
                    }
                }
                for (i in 0 until node.childCount) {
                    node.getChild(i)?.let { queue.add(it) }
                }
            } catch (_: Exception) {
                // 单个节点异常不中断整体遍历
            }
        }
        return if (lines.isEmpty()) "(屏幕无可读文本)" else lines.joinToString("\n")
    }

    private fun findFirstEditable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.poll() ?: continue
            if (node.isEditable && node.isVisibleToUser) return node
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }
}
