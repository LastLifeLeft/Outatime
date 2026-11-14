<h1 align="center">Outatime 0.0.2</h1>

<p align="center">Have you ever thought of mis-using <a href="https://github.com/JujuAdams/iota">Iota</a> and <a href="https://codeberg.org/offalynne/Input">Input</a> to create rollback netcode?</p>

&nbsp;

Well, I did.

This is very *rough*, *early*, *undocumented* and most importantly ***unsuported***, but it is used in one game and seems somewhat solid enough for cross-atlantic gameplay.

Input is buffered by [Input](https://codeberg.org/offalynne/Input) 10.5's Circular Buffer plug-in: during every tick the rollback manager browses it to that tick's frame, so `InputCheck()`, `InputPressed()` and the other checkers return the simulated frame's input for every seat (seat *p* is Input player *p*). Outside ticks Input returns live device state.
