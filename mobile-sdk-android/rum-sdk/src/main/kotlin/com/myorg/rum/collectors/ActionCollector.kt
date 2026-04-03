package com.myorg.rum.collectors

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.Window
import com.myorg.rum.EventBuffer
import com.myorg.rum.models.ConnectionContext
import com.myorg.rum.models.DeviceContext
import com.myorg.rum.models.RumContext
import com.myorg.rum.models.RumEvent

/**
 * 사용자 액션(터치) 수집기.
 *
 * Window.Callback 래퍼를 사용하여 Activity 의 터치 이벤트를 가로채고
 * tap 이벤트를 기록한다.
 *
 * - event_type: "action"
 * - event_name: "tap"
 * - payload: x, y 좌표, target view ID/class
 */
class ActionCollector(
    private val app: Application,
    private val buffer: EventBuffer,
    private val sessionProvider: () -> String,
    private val userProvider: () -> String,
    private val deviceId: String,
    private val appVersion: String,
    private val screenNameProvider: () -> String,
    private val deviceContextProvider: () -> DeviceContext,
    private val connectionContextProvider: () -> ConnectionContext
) : Application.ActivityLifecycleCallbacks {

    private val tag = "RumActionCollector"

    /** 액션 수집을 시작한다. */
    fun start() {
        app.registerActivityLifecycleCallbacks(this)
        Log.d(tag, "액션 수집기 시작됨")
    }

    /** 액션 수집을 중지한다. */
    fun stop() {
        app.unregisterActivityLifecycleCallbacks(this)
    }

    override fun onActivityStarted(activity: Activity) {
        val originalCallback = activity.window.callback
        activity.window.callback = RumWindowCallback(
            wrapped = originalCallback,
            activity = activity
        )
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}

    /** Window.Callback 래퍼 — 터치 이벤트를 가로채 RUM 이벤트로 변환 */
    private inner class RumWindowCallback(
        private val wrapped: Window.Callback?,
        private val activity: Activity
    ) : Window.Callback by (wrapped ?: NoOpWindowCallback) {

        override fun dispatchTouchEvent(event: MotionEvent?): Boolean {
            if (event != null && event.action == MotionEvent.ACTION_UP) {
                recordTap(event, activity)
            }
            return wrapped?.dispatchTouchEvent(event) ?: false
        }
    }

    private fun recordTap(event: MotionEvent, activity: Activity) {
        val x = event.x
        val y = event.y

        // 터치 좌표에서 뷰를 찾아 식별자를 추출한다
        val targetInfo = findTargetView(activity, x, y)

        buffer.add(
            RumEvent(
                sessionId = sessionProvider(),
                userId = userProvider(),
                deviceId = deviceId,
                timestamp = System.currentTimeMillis(),
                appVersion = appVersion,
                eventType = "action",
                eventName = "tap",
                payload = mapOf(
                    "x" to x,
                    "y" to y,
                    "target_id" to targetInfo.first,
                    "target_class" to targetInfo.second
                ),
                context = RumContext(
                    screenName = screenNameProvider(),
                    device = deviceContextProvider(),
                    connection = connectionContextProvider()
                )
            )
        )
    }

    /** 좌표에 해당하는 뷰의 (id 이름, 클래스명) 을 반환한다. */
    private fun findTargetView(activity: Activity, x: Float, y: Float): Pair<String, String> {
        val root = activity.window.decorView.rootView
        val target = findViewAt(root, x.toInt(), y.toInt())
        if (target != null) {
            val idName = runCatching {
                if (target.id != View.NO_ID) activity.resources.getResourceEntryName(target.id) else "no_id"
            }.getOrDefault("no_id")
            return idName to target.javaClass.simpleName
        }
        return "unknown" to "unknown"
    }

    /** 재귀적으로 주어진 좌표에 있는 최하위 자식 뷰를 반환한다. */
    private fun findViewAt(view: View, x: Int, y: Int): View? {
        if (!view.isShown) return null
        val loc = IntArray(2)
        view.getLocationOnScreen(loc)
        val rect = android.graphics.Rect(loc[0], loc[1], loc[0] + view.width, loc[1] + view.height)
        if (!rect.contains(x, y)) return null
        if (view is android.view.ViewGroup) {
            for (i in view.childCount - 1 downTo 0) {
                val child = findViewAt(view.getChildAt(i), x, y)
                if (child != null) return child
            }
        }
        return view
    }

    /** 기본 Window.Callback 구현 (래핑 대상이 null 일 때 사용) */
    private object NoOpWindowCallback : Window.Callback {
        override fun dispatchKeyEvent(event: android.view.KeyEvent?) = false
        override fun dispatchKeyShortcutEvent(event: android.view.KeyEvent?) = false
        override fun dispatchTouchEvent(event: MotionEvent?) = false
        override fun dispatchTrackballEvent(event: MotionEvent?) = false
        override fun dispatchGenericMotionEvent(event: MotionEvent?) = false
        override fun dispatchPopulateAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) = false
        override fun onCreatePanelView(featureId: Int) = null
        override fun onCreatePanelMenu(featureId: Int, menu: android.view.Menu?) = false
        override fun onPreparePanel(featureId: Int, view: View?, menu: android.view.Menu?) = false
        override fun onMenuOpened(featureId: Int, menu: android.view.Menu?) = false
        override fun onMenuItemSelected(featureId: Int, item: android.view.MenuItem?) = false
        override fun onWindowAttributesChanged(attrs: android.view.WindowManager.LayoutParams?) {}
        override fun onContentChanged() {}
        override fun onWindowFocusChanged(hasFocus: Boolean) {}
        override fun onAttachedToWindow() {}
        override fun onDetachedFromWindow() {}
        override fun onPanelClosed(featureId: Int, menu: android.view.Menu?) {}
        override fun onSearchRequested() = false
        override fun onSearchRequested(searchEvent: android.view.SearchEvent?) = false
        override fun onWindowStartingActionMode(callback: android.view.ActionMode.Callback?) = null
        override fun onWindowStartingActionMode(callback: android.view.ActionMode.Callback?, type: Int) = null
        override fun onActionModeStarted(mode: android.view.ActionMode?) {}
        override fun onActionModeFinished(mode: android.view.ActionMode?) {}
    }
}
