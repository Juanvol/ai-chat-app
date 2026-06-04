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
    private val pendingMainQueue = mutableListOf<PendingMessage>()
    private val pendingPetWindowQueue = mutableListOf<PendingMessage>()

    fun registerMain(messenger: BinaryMessenger) {
        mainMessenger = messenger
        pendingMainQueue.forEach { invokeMain(it.method, it.args) }
        pendingMainQueue.clear()
    }

    fun registerPetWindow(messenger: BinaryMessenger) {
        petWindowMessenger = messenger
        pendingPetWindowQueue.forEach { invokePetWindow(it.method, it.args) }
        pendingPetWindowQueue.clear()
    }

    fun clearMain() {
        mainMessenger = null
        pendingMainQueue.clear()
    }

    fun clearPetWindow() {
        petWindowMessenger = null
        pendingPetWindowQueue.clear()
    }

    fun invokeMain(method: String, args: Map<String, Any?>) {
        val target = mainMessenger
        if (target == null) {
            pendingMainQueue.add(PendingMessage(method, args))
            return
        }
        MethodChannel(target, CHANNEL_NAME).invokeMethod(method, args)
    }

    fun invokePetWindow(method: String, args: Map<String, Any?>) {
        val target = petWindowMessenger
        if (target == null) {
            pendingPetWindowQueue.add(PendingMessage(method, args))
            return
        }
        MethodChannel(target, CHANNEL_NAME).invokeMethod(method, args)
    }
}
