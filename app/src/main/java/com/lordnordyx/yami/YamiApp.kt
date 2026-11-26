package com.lordnordyx.yami

import android.app.Application
import com.lordnordyx.yami.data.GameRepository

class YamiApp : Application() {
    val repo: GameRepository by lazy { GameRepository(this) }
}
