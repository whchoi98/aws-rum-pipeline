package com.myorg.rum.utils

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.DisplayMetrics

/**
 * 디바이스 하드웨어 및 네트워크 정보 유틸리티.
 */
object DeviceInfo {

    /** Android OS 버전 문자열 (예: "Android 14") */
    fun osVersion(): String = "Android ${Build.VERSION.RELEASE}"

    /** 디바이스 모델명 (예: "Galaxy S24") */
    fun model(): String = Build.MODEL

    /**
     * 네트워크 연결 유형을 반환한다.
     * @return "wifi" | "4g" | "3g" | "2g" | "ethernet" | "none" | "unknown"
     */
    fun connectionType(context: Context): String {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return "none"
        val caps = cm.getNetworkCapabilities(network) ?: return "unknown"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> cellularGeneration(caps)
            else -> "unknown"
        }
    }

    /** 화면 해상도 및 밀도 정보 */
    fun screenMetrics(context: Context): Map<String, Any> {
        val metrics: DisplayMetrics = context.resources.displayMetrics
        return mapOf(
            "width_px" to metrics.widthPixels,
            "height_px" to metrics.heightPixels,
            "density" to metrics.density
        )
    }

    /** 셀룰러 세대 추정 (LinkDownstreamBandwidthKbps 기반) */
    private fun cellularGeneration(caps: NetworkCapabilities): String {
        val bw = caps.linkDownstreamBandwidthKbps
        return when {
            bw >= 20_000 -> "4g"
            bw >= 1_000  -> "3g"
            else         -> "2g"
        }
    }
}
