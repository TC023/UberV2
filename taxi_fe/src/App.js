import React from 'react';
import './App.css';

import Customer from './components/Customer';
import Driver from './components/Driver';

function App() {
  return (
    <div className="App">
      <Customer username="luciano"/>
      {/* <Customer username="dex"/> */}
      <Driver username="equidelol"/>
      <Driver username="alekock"/>
      <Driver username="alonsex"/>
    </div>
  );
}

export default App;
