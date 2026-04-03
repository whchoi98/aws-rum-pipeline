package com.myorg.rum

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.myorg.rum.collectors.ANRCollector
import com.myorg.rum.collectors.ActionCollector
import com.myorg.rum.collectors.CrashCollector
import com.myorg.rum.collectors.PerformanceCollector
import com.myorg.rum.collectors.ScreenCollector
import com.myorg.rum.models.ConnectionContext
import com.myorg.rum.models.DeviceContext
import com.myorg.rum.models.RumContext
import com.myorg.rum.models.RumEvent
import com.myorg.rum.utils.DeviceInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * RUM SDK 진입점 싱글톤.
 *
 * 사용 방법:
 * ```kotlin
 * // Application.onCreate() 에서 초기화
 * RumSDK.init(this, Config(endpoint = "https://...", apiKey = "key", appVersion = "1.0.0"))
 *
 * // 사용자 설정
 * RumSDK.setUser("user_12345")
 *
 * // 커스텀 이벤트
 * RumSDK.addCustomEvent("purchase", "button_click", mapOf("product_id" to "sku123"))
 * ```
 */
object RumSDK {

    private val tag = "RumSDK"

    private var config: Config? = null
    private var transport: Transport? = null
    private var buffer: EventBuffer? = null
    private var screenCollector: ScreenCollector? = null
    private var performanceCollector: PerformanceCollector? = null
    private var crashCollector: CrashCollector? = null
    private var anrCollector: ANRCollector? = null
    private var actionCollector: ActionCollector? = null

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    /** 세션 ID (앱 실행 단위) */
    @Volatile private var sessionId: String = UUID.randomUUID().toString()

    /** 디바이스 고유 ID (앱 설치 단위) */
    @Volatile private var deviceId: String = UUID.randomUUID().toString()

    /** 현재 사용자 ID */
    @Volatile private var userId: String = "anonymous"

    @Volatile private var initialized: Boolean = false

    /**
     * SDK 를 초기화한다. Application.onCreate() 에서 호출해야 한다.
     *
     * @param context Application Context
     * @param cfg     SDK 설정
     */
    fun init(context: Context, cfg: Config) {
        if (initialized) {
            Log.w(tag, "이미 초기화됨 — 재초기화 무시")
            return
        }

        val app = context.applicationContext as Application
        config = cfg

        // 디바이스 ID 를 SharedPreferences 에 영속 저장
        val prefs = app.getSharedPreferences("rum_sdk_prefs", Context.MODE_PRIVATE)
        deviceId = prefs.getString("device_id", null) ?: UUID.randomUUID().toString().also { id ->
            prefs.edit().putString("device_id", id).apply()
        }

        val t = Transport(cfg)
        transport = t

        val buf = EventBuffer(cfg, t, scope)
        buffer = buf
        buf.startTimer()

        // 디바이스 / 연결 정보 제공자
        val deviceCtxProvider: () -> DeviceContext = {
            DeviceContext(
                os = DeviceInfo.osVersion(),
                browser = "WebView",
                model = DeviceInfo.model()
            )
        }
        val connCtxProvider: () -> ConnectionContext = {
            ConnectionContext(
                type = DeviceInfo.connectionType(app),
                rtt = 0
            )
        }
        val rumCtxProvider: () -> RumContext = {
            RumContext(
                screenName = screenCollector?.currentScreenName ?: "",
                device = deviceCtxProvider(),
                connection = connCtxProvider()
            )
        }

        // 수집기 초기화
        screenCollector = ScreenCollector(
            app = app,
            buffer = buf,
            sessionProvider = ::sessionId,
            userProvider = ::userId,
            deviceId = deviceId,
            appVersion = cfg.appVersion,
            deviceContextProvider = deviceCtxProvider,
            connectionContextProvider = connCtxProvider
        ).also { it.start() }

        performanceCollector = PerformanceCollector(
            app = app,
            buffer = buf,
            sessionProvider = ::sessionId,
            userProvider = ::userId,
            deviceId = deviceId,
            appVersion = cfg.appVersion,
            deviceContextProvider = deviceCtxProvider,
            connectionContextProvider = connCtxProvider
        ).also { it.start() }

        crashCollector = CrashCollector(
            buffer = buf,
            sessionProvider = ::sessionId,
            userProvider = ::userId,
            deviceId = deviceId,
            appVersion = cfg.appVersion,
            screenNameProvider = { screenCollector?.currentScreenName ?: "" },
            contextProvider = rumCtxProvider
        ).also { it.start() }

        anrCollector = ANRCollector(
            buffer = buf,
            sessionProvider = ::sessionId,
            userProvider = ::userId,
            deviceId = deviceId,
            appVersion = cfg.appVersion,
            contextProvider = rumCtxProvider
        ).also { it.start() }

        actionCollector = ActionCollector(
            app = app,
            buffer = buf,
            sessionProvider = ::sessionId,
            userProvider = ::userId,
            deviceId = deviceId,
            appVersion = cfg.appVersion,
            screenNameProvider = { screenCollector?.currentScreenName ?: "" },
            deviceContextProvider = deviceCtxProvider,
            connectionContextProvider = connCtxProvider
        ).also { it.start() }

        // 앱 포어그라운드/백그라운드 감지
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) {
                // 백그라운드 진입 — 남은 이벤트 즉시 플러시
                scope.launch { buf.flushSync() }
            }

            override fun onStart(owner: LifecycleOwner) {
                // 포어그라운드 복귀 — 새 세션 ID 발급
                sessionId = UUID.randomUUID().toString()
                if (cfg.debug) Log.d(tag, "새 세션 시작: $sessionId")
            }
        })

        initialized = true
        if (cfg.debug) Log.d(tag, "RUM SDK 초기화 완료 (device=$deviceId)")
    }

    /**
     * 현재 사용자를 설정한다.
     * @param id 사용자 식별자 (예: "user_12345"). null 이면 "anonymous" 로 초기화.
     */
    fun setUser(id: String?) {
        userId = if (id.isNullOrBlank()) "anonymous" else id
        if (config?.debug == true) Log.d(tag, "사용자 설정: $userId")
    }

    /**
     * 커스텀 RUM 이벤트를 추가한다.
     *
     * @param eventType  이벤트 유형 (performance | action | error | navigation | resource)
     * @param eventName  이벤트 이름
     * @param payload    이벤트별 세부 데이터
     * @param screenName 현재 화면 이름 (생략 시 자동 감지)
     */
    fun addCustomEvent(
        eventType: String,
        eventName: String,
        payload: Map<String, Any> = emptyMap(),
        screenName: String? = null
    ) {
        val buf = buffer ?: run {
            Log.e(tag, "SDK 가 초기화되지 않았습니다. RumSDK.init() 을 먼저 호출하세요.")
            return
        }
        val cfg = config ?: return

        val event = RumEvent(
            sessionId = sessionId,
            userId = userId,
            deviceId = deviceId,
            timestamp = System.currentTimeMillis(),
            appVersion = cfg.appVersion,
            eventType = eventType,
            eventName = eventName,
            payload = payload,
            context = RumContext(
                screenName = screenName ?: screenCollector?.currentScreenName ?: ""
            )
        )
        buf.add(event)
    }

    /** 샘플링 여부를 결정한다. */
    private fun shouldSample(): Boolean {
        val rate = config?.sampleRate ?: 1.0
        return Math.random() < rate
    }

    /** SDK 초기화 여부 반환 (테스트 용도) */
    fun isInitialized(): Boolean = initialized

    /** 현재 세션 ID 반환 */
    fun getSessionId(): String = sessionId

    /** 현재 디바이스 ID 반환 */
    fun getDeviceId(): String = deviceId

    /** 테스트/재초기화를 위해 SDK 를 리셋한다. */
    internal fun reset() {
        screenCollector?.stop()
        performanceCollector?.stop()
        crashCollector?.stop()
        anrCollector?.stop()
        actionCollector?.stop()
        buffer?.stopTimer()
        buffer = null
        transport = null
        config = null
        initialized = false
        userId = "anonymous"
        sessionId = UUID.randomUUID().toString()
    }
}
