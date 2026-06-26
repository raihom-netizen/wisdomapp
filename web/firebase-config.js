/**
 * Configuração Firebase para o painel ADM HTML (WISDOMAPP).
 */
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.0/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/10.7.0/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/10.7.0/firebase-firestore.js";
import { getFunctions, httpsCallable } from "https://www.gstatic.com/firebasejs/10.7.0/firebase-functions.js";

const firebaseConfig = {
  apiKey: "AIzaSyDLm_BNjBptj5ribo0YGHQ9Nqd4l_Inl-4",
  authDomain: "wisdomapp-b9e98.firebaseapp.com",
  projectId: "wisdomapp-b9e98",
  storageBucket: "wisdomapp-b9e98.firebasestorage.app",
  messagingSenderId: "766524666378",
  appId: "1:766524666378:web:13900906f683df187f25f3",
  measurementId: "G-Z6D218TWFY",
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);
const functions = getFunctions(app, "us-central1");

export { app, db, auth, functions, httpsCallable };
