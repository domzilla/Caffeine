# Caffeine Lid — قفل الجهاز والعمل والغطاء مغلق

Fork of [domzilla/Caffeine](https://github.com/domzilla/Caffeine) with an experimental protected lid session for macOS.

**العربية:** من الإعدادات اختر «قفل الجهاز والعمل والغطاء مغلق…». يُطلب إذن المسؤول مرة واحدة لتثبيت المساعد. يقفل جهازك فورًا ثم يبقي المهام تعمل مع إطفاء الشاشات، ويمكنك إغلاق الغطاء. عند العودة يلزم فتح قفل حساب Mac، وتنتهي جلسة الغطاء المحمي بعد فتح القفل. يلزم اختبار الغطاء والطاقة فعليًا على جهازك؛ هذه نسخة تجريبية وليست إصدارًا موثقًا من Apple.

**English:** A dedicated action locks macOS before keeping work running with the lid closed and displays off. Administrator approval is needed only for the first helper installation. Unlocking ends the protected session. Hardware verification is still required.

Build with `bash scripts/build-lid.sh`. Read [usage, helper removal, recovery, and validation](docs/PROTECTED-LID.md) before testing.

---

## Upstream README

<img src="https://github.caffeine-app.net/assets/icon.png" alt="Icon" width="239"/>

# Caffeine
### Don't let your Mac fall asleep.

Caffeine is a tiny program that keeps your Mac awake, useful for ensuring that long running tasks aren't interrupted by your computer going to sleep.

### Installation

Download Caffeine at https://caffeine-app.net and drag it into your Applications folder, then double-click the icon to launch it.

### Usage

Caffeine puts a coffee cup icon in the right side of your menu bar. Click the cup to toggle whether Caffeine is active or not -- a full cup means Caffeine will prevent your Mac from automatically going to sleep, dimming the screen or starting screen savers. An empty cup means your Mac will sleep normally.

<img src="https://github.caffeine-app.net/assets/menubar.png" alt="Menubar" width="277"/>

For more control, right-click (or ⌘-click) the icon to show the menu. From here, you can access the preferences window or set a timeout if you only need Caffeine to prevent sleep for a little while.

<img src="https://github.caffeine-app.net/assets/menu.png" alt="Menu" width="293"/>

Caffeine is intended to be simple, yet powerful. Options you can configure include whether to start Caffeine automatically every time you start up your Mac, whether Caffeine should activate every time it starts, and a default duration if you always want Caffeine to turn itself off after a set time.

<img src="https://github.caffeine-app.net/assets/preferences.png" alt="Preferences" width="645"/>

### FAQ

##### Is this the same Caffeine that I've used before?

Yes! Tomas Franzén of Lighthead Software originally developed Caffeine in 2006, and it has been a well known and loved utility for Mac users for many years. Its simplicity has allowed it to continue working perfectly long after active development had ceased.

In 2018, Michael Jones (IntelliScape Computer Solutions) reached out to Tomas to inquire if they could continue development of Caffeine.

Tomas has graciously provided the source code under an open source license, allowing IntelliScape Computer Solutions to continue developing Caffeine where he left off.

##### Does this work with macOS 10.x?

No, this version requires at least macOS 11 (Big Sur). Caffeine for macOS Yosemite or later (including Catalina) is available at: https://www.intelliscapesolutions.com/apps/caffeine/

##### How is Caffeine different or better than alternatives (such as Amphetamine, KeepingYouAwake, etc)?

Due to the long period of inactivity for Caffeine, a lot of different and great options have been developed. While the alternatives are great apps and definitely worth your consideration, we believe that Caffeine's power lies in its simplicity and ease of use.

### Support

If you have questions, comments or other feedback get in touch at https://caffeine-app.net/support.