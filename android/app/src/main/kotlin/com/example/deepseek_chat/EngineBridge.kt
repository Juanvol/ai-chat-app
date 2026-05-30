package com.example.deepseek_chat

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object EngineBridge {
    private const val CHANNEL_NAME = "com.example.deepseek_chat/pet_agent_bridge"

    var mainMessenger: BinaryMessenger? = null
        private set
    var petWindowMessenger: BinaryMessenger? = null
        private set

    private data class PendingMessage(val method: String, val args: Map<String, Any?>)
    private val pendingQueue = mutableListOf<PendingMessage>()

    fun registerMain(messenger: BinaryMessenger) {
        mainMessenger = messenger
        pendingQueue.forEach { invokeMain(it.method, it.args) }
        pendingQueue.clear()
    }

    fun registerPetWindow(messenger: BinaryMessenger) {
        petWindowMessenger = messenger
    }

    fun clearMain() {
        mainMessenger = null
    }

    fun clearPetWindow() {
        petWindowMessenger = null
    }

    fun invokeMain(method: String, args: Map<String, Any?>) {
        val target = mainMessenger
        if (target == null) {
            pendingQueue.add(PendingMessage(method, args))
            return
        }
        MethodChannel(target, CHANNEL_NAME).invokeMethod(method, args)
    }

    fun invokePetWindow(method: String, args: Map<String, Any?>) {
        petWindowMessenger?.let {
            MethodChannel(it, CHANNEL_NAME).invokeMethod(method, args)
        }
    }
}
